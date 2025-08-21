/*Surpressing unnecessary output*/
ods graphics off; ods exclude all; ods results off; options nonotes;

/*Import and cleaning*/
filename REFFILE '/export/viya/homes/43203299@mynwu.ac.za/BWIN 621 ASSIGNMENT 1/sandbox/Shahil Mathapershad/SmallBusinessLoans.xlsx';
proc import datafile=REFFILE dbms=xlsx out=loans_data replace; getnames=yes; run;

data loans_clean;
  set loans_data;
  if RevLineCr in ('Y','T') then RevLineCr_num=1; else RevLineCr_num=0;
  drop RevLineCr; rename RevLineCr_num=RevLineCr;
  if FranchiseCode<=1 then FranchiseCode=0; else FranchiseCode=1;
  drop Name LoanNr_ChkDgt Zip New WrittenOff BalanceGross;
run;

/*Full model*/
ods output ParameterEstimates=old_params;
proc logistic data=loans_clean(where=(Selected=1)) plots=none;
  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;
  model Default(event='1') =
        Term NoEmp CreateJob RetainedJob FranchiseCode
        UrbanRural RevLineCr DisbursementGross RealEstate
        Portion Recession;
  score data=loans_clean(where=(Selected=0))
        out=old_valid_scored(keep=Default P_1 rename=(P_1=PD_old))
        outroc=old_valid_roc;
run;

/* Full model metrics */
proc sql noprint;
  select _PROB_ into :cut_old
  from old_valid_roc
  having (_SENSIT_ - _1MSPEC_) = max((_SENSIT_ - _1MSPEC_));
  create table perf_old_v as
    select "Old" as Model length=6,
           mean((case when PD_old>=0.5 then 1 else 0 end) ne Default)  as ValErr_0_5,
           mean((case when PD_old>=&cut_old then 1 else 0 end) ne Default) as ValErr_Youden
    from old_valid_scored;
quit;

proc sort data=old_valid_roc(keep=_1MSPEC_ _SENSIT_) out=old_roc_s; by _1MSPEC_; run;
data old_auc; set old_roc_s end=last; retain prev_fpr prev_tpr auc 0;
  fpr=_1MSPEC_; tpr=_SENSIT_;
  if _n_>1 then auc + (fpr-prev_fpr)*(tpr+prev_tpr)/2;
  prev_fpr=fpr; prev_tpr=tpr;
  if last then output;
  keep auc;
run;

/* Reduced model */
ods output ParameterEstimates=new_params;
proc logistic data=loans_clean(where=(Selected=1)) plots=none;
  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;
  model Default(event='1') =
        Term NoEmp CreateJob RetainedJob FranchiseCode
        UrbanRural RevLineCr DisbursementGross RealEstate
        Portion Recession
        / selection=stepwise slentry=0.05 slstay=0.05;
  score data=loans_clean(where=(Selected=0))
        out=new_valid_scored(keep=Default P_1 rename=(P_1=PD_new))
        outroc=new_valid_roc;
run;

/* Reduced model metrics */
proc sql noprint;
  select _PROB_ into :cut_new
  from new_valid_roc
  having (_SENSIT_ - _1MSPEC_) = max((_SENSIT_ - _1MSPEC_));
  create table perf_new_v as
    select "New" as Model length=6,
           mean((case when PD_new>=0.5 then 1 else 0 end) ne Default)  as ValErr_0_5,
           mean((case when PD_new>=&cut_new then 1 else 0 end) ne Default) as ValErr_Youden
    from new_valid_scored;
quit;

proc sort data=new_valid_roc(keep=_1MSPEC_ _SENSIT_) out=new_roc_s; by _1MSPEC_; run;
data new_auc; set new_roc_s end=last; retain prev_fpr prev_tpr auc 0;
  fpr=_1MSPEC_; tpr=_SENSIT_;
  if _n_>1 then auc + (fpr-prev_fpr)*(tpr+prev_tpr)/2;
  prev_fpr=fpr; prev_tpr=tpr;
  if last then output;
  keep auc;
run;

/*10-fold CV error @0.5 for both models */
proc surveyselect data=loans_clean(where=(Selected=1))
                  out=cv_folds seed=271828 groups=10; run;

/* Full model CV */
%let workdir=%sysfunc(pathname(work));
filename cv_old "&workdir./cv_old.sas";
data _null_; file cv_old lrecl=32767;
  do k=1 to 10;
    put 'proc logistic data=cv_folds(where=(GroupID ne ' k ')) noprint;';
    put '  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;';
    put "  model Default(event='1') = Term NoEmp CreateJob RetainedJob FranchiseCode UrbanRural RevLineCr DisbursementGross RealEstate Portion Recession;";
    put '  score data=cv_folds(where=(GroupID=' k ')) out=cv_old_' k ' (keep=Default P_1 rename=(P_1=PD));';
    put 'run;';
  end;
run;
%include cv_old;

data old_cv_all; set cv_old_:; run;
proc sql; create table old_cv_err as
  select mean((case when PD>=0.5 then 1 else 0 end) ne Default) as CVErr_0_5
  from old_cv_all; quit;

/* Reduced model CV */
filename cv_new "&workdir./cv_new.sas";
data _null_; file cv_new lrecl=32767;
  do k=1 to 10;
    put 'proc logistic data=cv_folds(where=(GroupID ne ' k ')) noprint;';
    put '  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;';
    put "  model Default(event='1') = Term NoEmp CreateJob RetainedJob FranchiseCode UrbanRural RevLineCr DisbursementGross RealEstate Portion Recession / selection=stepwise slentry=0.05 slstay=0.05;";
    put '  score data=cv_folds(where=(GroupID=' k ')) out=cv_new_' k ' (keep=Default P_1 rename=(P_1=PD));';
    put 'run;';
  end;
run;
%include cv_new;

data new_cv_all; set cv_new_:; run;
proc sql; create table new_cv_err as
  select mean((case when PD>=0.5 then 1 else 0 end) ne Default) as CVErr_0_5
  from new_cv_all; quit;

/* Creating model performance tables */
proc sql;
  create table old_auc2 as select 'Old' as Model length=6, auc from old_auc;
  create table new_auc2 as select 'New' as Model length=6, auc from new_auc;

  create table perf_old as
    select 'Old' as Model length=6, v.ValErr_0_5, v.ValErr_Youden, a.auc as AUC, c.CVErr_0_5
    from perf_old_v v, old_auc2 a, old_cv_err c;

  create table perf_new as
    select 'New' as Model length=6, v.ValErr_0_5, v.ValErr_Youden, a.auc as AUC, c.CVErr_0_5
    from perf_new_v v, new_auc2 a, new_cv_err c;

  create table perf as
    select * from perf_old
    union all
    select * from perf_new;
quit;

/*Surpressing unnecessary outptus */
ods exclude none; ods results on; options notes;

/* coefficients */
title "OLD — Coefficients";         proc print data=old_params noobs; run;
title "NEW (stepwise) — Coefficients"; proc print data=new_params noobs; run;

/* confusion matrices on validation */
proc format;
  value pred_half    low-<0.5='0'  0.5-high='1';
  value pred_yj_old  low-<&cut_old='0'  &cut_old-high='1';
  value pred_yj_new  low-<&cut_new='0'  &cut_new-high='1';
run;

title "OLD — Confusion Matrix (Validation @0.5)";
proc freq data=old_valid_scored;
  tables Default*PD_old / norow nocol nopercent;
  format PD_old pred_half.;
run;

title "OLD — Confusion Matrix (Validation @Youden)";
proc freq data=old_valid_scored;
  tables Default*PD_old / norow nocol nopercent;
  format PD_old pred_yj_old.;
run;

title "NEW — Confusion Matrix (Validation @0.5)";
proc freq data=new_valid_scored;
  tables Default*PD_new / norow nocol nopercent;
  format PD_new pred_half.;
run;

title "NEW — Confusion Matrix (Validation @Youden)";
proc freq data=new_valid_scored;
  tables Default*PD_new / norow nocol nopercent;
  format PD_new pred_yj_new.;
run;

/* performance table */
title "Validation & 10-fold CV performance";
proc print data=perf noobs label;
  label ValErr_0_5='Error @0.5'
        ValErr_Youden='Error @Youden'
        AUC='AUC (validation)'
        CVErr_0_5='10-fold CV Error @0.5';
run; title;



