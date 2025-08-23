/*===============================================================
  06_validation.sas — model validation 
  - Uses MODELS from 04_model.sas
  - Scores HOLD if available, else DEV
  - Youden-J cut, AUC (trapezoid), confusion matrices
  - 10-fold CV on DEV (@0.5)
  - ROC overlay (Old vs New) saved to results/validation/plots
===============================================================*/

/* keep the log tidy for heavy steps */
ods graphics off; ods exclude all; ods results off; options nonotes;

/* env + libs */
%let _pgm=%sysfunc(dequote(&_SASPROGRAMFILE));
%let _dir=%substr(&_pgm,1,%eval(%length(&_pgm)-%length(%scan(&_pgm,-1,'/'))-1));
%include "&_dir/00_env.sas";

/* helpers */
%macro ensure_models;
  %if %sysfunc(libref(models)) %then %do;
    %let _models_path=&RES_PATH/models;
    %if %sysfunc(fileexist("&_models_path"))=0 %then %do;
      data _null_; rc=dcreate('models',"&RES_PATH"); run;
    %end;
    libname models "&_models_path";
  %end;
%mend;
%macro ensure_val;
  %if %sysfunc(libref(val)) %then %do;
    %let _val_path=&RES_PATH/validation;
    %if %sysfunc(fileexist("&_val_path"))=0 %then %do;
      data _null_; rc=dcreate('validation',"&RES_PATH"); run;
    %end;
    libname val "&_val_path";
  %end;
%mend;
%macro assert(ds,msg);
  %if %sysfunc(exist(&ds))=0 %then %do; %put ERROR: &msg; %abort cancel; %end;
%mend;

/* mount libs + guards */
%ensure_models
%ensure_val
%assert(models.logit_full_model, Missing MODELS.LOGIT_FULL_MODEL. Run 04_model.sas.)
%assert(models.logit_step_model, Missing MODELS.LOGIT_STEP_MODEL. Run 04_model.sas.)
%assert(wrk.dev, WRK.DEV not available. Run 03_clean.sas first.)

/* pick validation table */
%global VALSET TAG;
%if %sysfunc(exist(wrk.hold)) %then %do; %let VALSET=wrk.hold; %let TAG=hold; %end;
%else %do; %let VALSET=wrk.dev; %let TAG=dev; %end;

/* predictor list (must match 04_model.sas for CV fits) */
%let xlist = Term NoEmp CreateJob RetainedJob FranchiseCode
             UrbanRural RevLineCr RealEstate Recession
             DisbursementGross Portion;

/*====================== A) VALIDATION: score + metrics =====================*/

/* FULL on validation */
proc logistic inmodel=models.logit_full_model noprint;
  score data=&VALSET
        out=val.old_valid_scored(keep=Default P_1 rename=(P_1=PD_old))
        outroc=val.old_valid_roc
        fitstat;
run;

/* STEPWISE on validation */
proc logistic inmodel=models.logit_step_model noprint;
  score data=&VALSET
        out=val.new_valid_scored(keep=Default P_1 rename=(P_1=PD_new))
        outroc=val.new_valid_roc
        fitstat;
run;

/* Youden-J cuts */
%global cut_old cut_new;
proc sql noprint;
  select _PROB_ into :cut_old
  from val.old_valid_roc
  having (_SENSIT_ - _1MSPEC_) = max((_SENSIT_ - _1MSPEC_));
  select _PROB_ into :cut_new
  from val.new_valid_roc
  having (_SENSIT_ - _1MSPEC_) = max((_SENSIT_ - _1MSPEC_));
quit;

/* if ROC were empty (edge), default to 0.5 */
%macro _default_youden_cuts;
  %if %length(%superq(cut_old))=0 %then %let cut_old=0.5;
  %if %length(%superq(cut_new))=0 %then %let cut_new=0.5;
%mend; %_default_youden_cuts

/* errors @0.5 and @Youden */
proc sql noprint;
  create table val.perf_old_v as
  select "Old" as Model length=6,
         mean((case when PD_old>=0.5 then 1 else 0 end) ne Default)      as ValErr_0_5,
         mean((case when PD_old>=&cut_old then 1 else 0 end) ne Default) as ValErr_Youden
  from val.old_valid_scored;

  create table val.perf_new_v as
  select "New" as Model length=6,
         mean((case when PD_new>=0.5 then 1 else 0 end) ne Default)      as ValErr_0_5,
         mean((case when PD_new>=&cut_new then 1 else 0 end) ne Default) as ValErr_Youden
  from val.new_valid_scored;
quit;

/* AUC via trapezoid */
proc sort data=val.old_valid_roc(keep=_1MSPEC_ _SENSIT_) out=val.old_roc_s; by _1MSPEC_; run;
data val.old_auc; set val.old_roc_s end=last; retain prev_fpr prev_tpr auc 0;
  fpr=_1MSPEC_; tpr=_SENSIT_;
  if _n_>1 then auc + (fpr-prev_fpr)*(tpr+prev_tpr)/2;
  prev_fpr=fpr; prev_tpr=tpr;
  if last then output;
  keep auc;
run;

proc sort data=val.new_valid_roc(keep=_1MSPEC_ _SENSIT_) out=val.new_roc_s; by _1MSPEC_; run;
data val.new_auc; set val.new_roc_s end=last; retain prev_fpr prev_tpr auc 0;
  fpr=_1MSPEC_; tpr=_SENSIT_;
  if _n_>1 then auc + (fpr-prev_fpr)*(tpr+prev_tpr)/2;
  prev_fpr=fpr; prev_tpr=tpr;
  if last then output;
  keep auc;
run;

/*====================== B) 10-fold CV on DEV (@0.5) ========================*/
proc surveyselect data=wrk.dev out=val.cv_folds seed=271828 groups=10; run;

/* FULL CV (same technique as Shahil: generate tiny code) */
%let workdir=%sysfunc(pathname(work));
filename cv_old "&workdir./cv_old.sas";
data _null_; file cv_old lrecl=32767;
  do k=1 to 10;
    put 'proc logistic data=val.cv_folds(where=(GroupID ne ' k ')) noprint;';
    put '  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;';
    put "  model Default(event='1') = &xlist;";
    put '  score data=val.cv_folds(where=(GroupID=' k ')) out=val.cv_old_' k ' (keep=Default P_1 rename=(P_1=PD));';
    put 'run;';
  end;
run;
%include cv_old;

data val.old_cv_all; set val.cv_old_:; run;
proc sql noprint;
  create table val.old_cv_err as
  select mean((case when PD>=0.5 then 1 else 0 end) ne Default) as CVErr_0_5
  from val.old_cv_all;
quit;

/* STEPWISE CV */
filename cv_new "&workdir./cv_new.sas";
data _null_; file cv_new lrecl=32767;
  do k=1 to 10;
    put 'proc logistic data=val.cv_folds(where=(GroupID ne ' k ')) noprint;';
    put '  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;';
    put "  model Default(event='1') = &xlist / selection=stepwise slentry=0.05 slstay=0.05;";
    put '  score data=val.cv_folds(where=(GroupID=' k ')) out=val.cv_new_' k ' (keep=Default P_1 rename=(P_1=PD));';
    put 'run;';
  end;
run;
%include cv_new;

data val.new_cv_all; set val.cv_new_:; run;
proc sql noprint;
  create table val.new_cv_err as
  select mean((case when PD>=0.5 then 1 else 0 end) ne Default) as CVErr_0_5
  from val.new_cv_all;
quit;

/*====================== C) Combine performance =============================*/
proc sql;
  create table val.old_auc2 as select 'Old' as Model length=6, auc from val.old_auc;
  create table val.new_auc2 as select 'New' as Model length=6, auc from val.new_auc;

  create table val.perf_old as
    select 'Old' as Model length=6, v.ValErr_0_5, v.ValErr_Youden, a.auc as AUC, c.CVErr_0_5
    from val.perf_old_v v, val.old_auc2 a, val.old_cv_err c;

  create table val.perf_new as
    select 'New' as Model length=6, v.ValErr_0_5, v.ValErr_Youden, a.auc as AUC, c.CVErr_0_5
    from val.perf_new_v v, val.new_auc2 a, val.new_cv_err c;

  create table val.perf as
    select * from val.perf_old
    union all
    select * from val.perf_new;
quit;

/*====================== D) ROC plots (overlay) =============================*/
/* turn results back on for plots */
ods results on;
ods exclude none;
ods graphics on;

/* AUCs for legend labels */
proc sql noprint;
  select put(auc,6.3) into :auc_old from val.old_auc;
  select put(auc,6.3) into :auc_new from val.new_auc;
quit;

/* stack ROC points */
data val.roc_both;
  length Model $6 ModelLabel $24;
  set val.old_valid_roc(in=a keep=_1MSPEC_ _SENSIT_)
      val.new_valid_roc(in=b keep=_1MSPEC_ _SENSIT_);
  if a then do; Model='Old'; ModelLabel=cats('Old (AUC=', "&auc_old", ')'); end;
  else if b then do; Model='New'; ModelLabel=cats('New (AUC=', "&auc_new", ')'); end;
  rename _1MSPEC_=FPR _SENSIT_=TPR;
run;

/* plots folder */
%let _valplot = &RES_PATH/validation/plots;
%if %sysfunc(fileexist("&_valplot"))=0 %then %do;
  data _null_; rc=dcreate('validation',"&RES_PATH"); run;
  data _null_; rc=dcreate('plots',"&RES_PATH/validation"); run;
%end;

/* save ROC overlay PNG */
ods listing gpath="&_valplot";
ods graphics / reset width=7in height=5in imagename="ROC_Validation_Overlay";
title "Validation ROC — Old vs New";
proc sgplot data=val.roc_both noautolegend;
  series x=FPR y=TPR / group=ModelLabel lineattrs=(thickness=2);
  lineparm x=0 y=0 slope=1 / transparency=0.5;
  xaxis label="False Positive Rate (1 - Specificity)" values=(0 to 1 by 0.1);
  yaxis label="True Positive Rate (Sensitivity)"      values=(0 to 1 by 0.1);
  keylegend / title="Models";
run; title;

/*====================== E) Turn output back on + prints =====================*/
ods exclude none; ods results on; options notes;

/* coefficients from training */
title "OLD — Coefficients";            proc print data=models.full_params noobs; run;
title "NEW (stepwise) — Coefficients"; proc print data=models.step_params noobs; run;

/* confusion matrices on validation */
proc format;
  value pred_half    low-<0.5='0'  0.5-high='1';
  value pred_yj_old  low-<&cut_old='0'  &cut_old-high='1';
  value pred_yj_new  low-<&cut_new='0'  &cut_new-high='1';
run;

title "OLD — Confusion Matrix (Validation @0.5)";
proc freq data=val.old_valid_scored;
  tables Default*PD_old / norow nocol nopercent;
  format PD_old pred_half.;
run;

title "OLD — Confusion Matrix (Validation @Youden)";
proc freq data=val.old_valid_scored;
  tables Default*PD_old / norow nocol nopercent;
  format PD_old pred_yj_old.;
run;

title "NEW — Confusion Matrix (Validation @0.5)";
proc freq data=val.new_valid_scored;
  tables Default*PD_new / norow nocol nopercent;
  format PD_new pred_half.;
run;

title "NEW — Confusion Matrix (Validation @Youden)";
proc freq data=val.new_valid_scored;
  tables Default*PD_new / norow nocol nopercent;
  format PD_new pred_yj_new.;
run;

/* performance table */
title "Validation & 10-fold CV performance";
proc print data=val.perf noobs label;
  label ValErr_0_5='Error @0.5'
        ValErr_Youden='Error @Youden'
        AUC='AUC (validation)'
        CVErr_0_5='10-fold CV Error @0.5';
run; title;
