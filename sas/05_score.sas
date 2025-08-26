/*===============================================================
  05_score.sas — production scoring (PD + Points) with console output
  - Loads env (00_env.sas)
  - Ensures MODELS and SCORE libs (results/models, results/score)
  - Picks table to score: WRK.HOLD else WRK.DEV
  - Scores BOTH saved models:
      MODELS.LOGIT_FULL_MODEL  → PD_full
      MODELS.LOGIT_STEP_MODEL  → PD_step
  - Writes SCORE.&tag._SCORED and shows preview + summary
  - Coded by Tapiwa Gweshe
===============================================================*/

/* A) Environment */
%let _pgm = %sysfunc(dequote(&_SASPROGRAMFILE));
%let _dir = %substr(&_pgm,1,%eval(%length(&_pgm)-%length(%scan(&_pgm,-1,'/'))-1));
%include "&_dir/00_env.sas";

/* B) Libraries (create if needed, then ASSIGN) */
%macro ensure_models;
  %if %sysfunc(libref(models)) %then %do;
    %let _models_path=&RES_PATH/models;
    %if %sysfunc(fileexist("&_models_path"))=0 %then %do;
      data _null_; rc=dcreate('models',"&RES_PATH"); run;
    %end;
    libname models "&_models_path";
  %end;
%mend;

%macro ensure_score;
  %if %sysfunc(libref(score)) %then %do;
    %let _score_path=&RES_PATH/score;
    %if %sysfunc(fileexist("&_score_path"))=0 %then %do;
      data _null_; rc=dcreate('score',"&RES_PATH"); run;
    %end;
    libname score "&_score_path";
  %end;
%mend;

%ensure_models
%ensure_score

/* C) Guardrails */
%macro assert(ds,msg);
  %if %sysfunc(exist(&ds))=0 %then %do; %put ERROR: &msg; %abort cancel; %end;
%mend;

%assert(models.logit_full_model , Missing MODELS.LOGIT_FULL_MODEL. Run 04_model.sas.)
%assert(models.logit_step_model , Missing MODELS.LOGIT_STEP_MODEL. Run 04_model.sas.)

/* D) Pick dataset to score (avoid %ELSE %IF gotcha) */
%global _toscore _tag;
%macro pick_toscore;
  %if %sysfunc(exist(wrk.hold)) %then %do; %let _toscore=wrk.hold; %let _tag=hold; %return; %end;
  %if %sysfunc(exist(wrk.dev))  %then %do; %let _toscore=wrk.dev;  %let _tag=dev;  %return; %end;
  %put ERROR: No WRK.HOLD or WRK.DEV available. Run 03_clean.sas.;
  %abort cancel;
%mend;
%pick_toscore

/* E) Add row id for safe merge */
data _toscore_;
  set &_toscore;
  _rid_=_n_;
run;

/* F) Score BOTH models (probability of default only) */
proc logistic inmodel=models.logit_full_model noprint;
  score data=_toscore_
        out=_full_scored(keep=_rid_ Default P_1 rename=(P_1=PD_full));
run;

proc logistic inmodel=models.logit_step_model noprint;
  score data=_toscore_
        out=_step_scored(keep=_rid_ Default P_1 rename=(P_1=PD_step));
run;

/* G) Merge and PD difference → SCORE.&tag._SCORED */
data score.&_tag._scored;
  merge _full_scored _step_scored;
  by _rid_;
  PD_diff = PD_step - PD_full;
run;

/* H) PD → Points (PDO method) with clipping to avoid infinities */
%let BaseScore = 600;   /* score at BaseOdds */
%let BaseOdds  = 50;    /* non-default:default odds at BaseScore */
%let PDO       = 20;    /* points to double the odds */
%let Pmin      = 1e-6;
%let Pmax      = 0.999999;

data score.&_tag._scored;
  set score.&_tag._scored;
  _p = min(max(PD_full,&Pmin),&Pmax);
  _q = min(max(PD_step,&Pmin),&Pmax);

  Points_full = &BaseScore + (&PDO/log(2))*( log((1-_p)/_p) - log(&BaseOdds) );
  Points_step = &BaseScore + (&PDO/log(2))*( log((1-_q)/_q) - log(&BaseOdds) );

  drop _p _q;
run;

/* I) Console output — enable Results for driver runs */
ods exclude none; ods results on;

/* Preview (first 15) */
title "Scoring preview (&_tag.): PDs and Points (first 15)";
proc print data=score.&_tag._scored(obs=15) noobs;
  var Default PD_full PD_step PD_diff Points_full Points_step;
run;

/* Summary */
title "Scoring summary (&_tag.): PDs and Points";
proc means data=score.&_tag._scored n mean p25 p50 p75 min max maxdec=4;
  var PD_full PD_step PD_diff Points_full Points_step;
run; title;

/* ---------- Confusion matrix + metrics for any (PD, cut) ---------- */
%macro _cm_metrics(data=, y=Default, p=, cut=, label=);
  /* 1) classify */
  data __tmp;
    set &data;
    length _pred 8;
    _pred = (&p >= &cut);
  run;

  /* 2) confusion counts */
  proc freq data=__tmp noprint;
    tables &y.*_pred / out=__cm;
  run;

  /* 3) pull TP/TN/FP/FN into macro vars */
  proc sql noprint;
    select sum(count) into :_N      from __cm;
    select sum(count) into :_TP     from __cm where &y.=1 and _pred=1;
    select sum(count) into :_TN     from __cm where &y.=0 and _pred=0;
    select sum(count) into :_FP     from __cm where &y.=0 and _pred=1;
    select sum(count) into :_FN     from __cm where &y.=1 and _pred=0;
  quit;

  /* 4) derive metrics (guard zero-denominators) */
  data __metrics;
    length Model $48;
    N  = input(symget('_N'), best.);
    TP = input(symget('_TP'),best.);
    TN = input(symget('_TN'),best.);
    FP = input(symget('_FP'),best.);
    FN = input(symget('_FN'),best.);

    Model = "&label"; Cut = &cut;
    Accuracy     = (TP+TN)/max(N,1);
    Sensitivity  = TP/max(TP+FN,1);
    Specificity  = TN/max(TN+FP,1);
    Precision    = TP/max(TP+FP,1);
    NPV          = TN/max(TN+FN,1);
    FPR          = 1-Specificity;
    FNR          = 1-Sensitivity;
    F1           = ifn(Precision+Sensitivity>0, 2*Precision*Sensitivity/(Precision+Sensitivity), .);
    BalancedAcc  = (Sensitivity+Specificity)/2;
    YoudenJ      = Sensitivity + Specificity - 1;
    Prevalence   = (TP+FN)/max(N,1);
    PredPosRate  = (TP+FP)/max(N,1);
    MCC_den      = sqrt(max((TP+FP)*(TP+FN)*(TN+FP)*(TN+FN),1));
    MCC          = ((TP*TN)-(FP*FN)) / MCC_den;
    drop MCC_den;
  run;

  title "Confusion matrix — &label";
  proc print data=__cm noobs; run;
  title "Metrics — &label";
  proc print data=__metrics noobs; run;
  title;

  proc datasets nolist; delete __tmp __cm __metrics; quit;
%mend;

/* ---------- Wrapper: run for Full/Step at 0.5 and Youden-J if available ---------- */
%macro confusion_if_default;
  %local dsid pos rc cut_full cut_step;

  /* only run if Default is present */
  %let dsid=%sysfunc(open(score.&_tag._scored,i));
  %let pos=%sysfunc(varnum(&dsid,Default));
  %let rc=%sysfunc(close(&dsid));
  %if &pos=0 %then %return;

  /* @0.5 for both models */
  %_cm_metrics(data=score.&_tag._scored, y=Default, p=PD_full, cut=0.5, label=Full @0.5 (&_tag.));
  %_cm_metrics(data=score.&_tag._scored, y=Default, p=PD_step, cut=0.5, label=Stepwise @0.5 (&_tag.));

  /* Youden-J thresholds if ROC tables exist */
  %if %sysfunc(exist(score.&_tag._roc_full)) %then %do;
    proc sql noprint;
      select _PROB_ into :cut_full
      from score.&_tag._roc_full
      having (_SENSIT_ - _1MSPEC_) = max((_SENSIT_ - _1MSPEC_));
    quit;
    %if %sysevalf(%superq(cut_full)^=,boolean) %then
      %_cm_metrics(data=score.&_tag._scored, y=Default, p=PD_full, cut=&cut_full, label=Full @Youden (&_tag.));
  %end;

  %if %sysfunc(exist(score.&_tag._roc_step)) %then %do;
    proc sql noprint;
      select _PROB_ into :cut_step
      from score.&_tag._roc_step
      having (_SENSIT_ - _1MSPEC_) = max((_SENSIT_ - _1MSPEC_));
    quit;
    %if %sysevalf(%superq(cut_step)^=,boolean) %then
      %_cm_metrics(data=score.&_tag._scored, y=Default, p=PD_step, cut=&cut_step, label=Stepwise @Youden (&_tag.));
  %end;
%mend;
%confusion_if_default


/* Friendly path note (shows in Log) */
%put NOTE: Scored table -> SCORE.&_tag._SCORED  (%sysfunc(pathname(score))).;
