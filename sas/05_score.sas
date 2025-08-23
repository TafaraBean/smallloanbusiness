/*===============================================================
  05_score.sas — score hold-out (PD) + create points score
  - Loads env and model artifact (MODELS lib)
  - Scores WRK.HOLD if present, else scores WRK.DEV
  - Outputs scored table + ROC + simple cuts (0.5, Youden-J)
  - Adds POINTS column from PD using BaseScore/BaseOdds/PDO
===============================================================*/

/* 0) Bootstrap env and ensure pre-reqs */
%let _pgm=%sysfunc(dequote(&_SASPROGRAMFILE));
%let _dir=%substr(&_pgm,1,%eval(%length(&_pgm)-%length(%scan(&_pgm,-1,'/'))-1));
%include "&_dir/00_env.sas";

/* Ensure MODELS and SCORE libs (results/models, results/score) */
%macro ensure_models;
  %if %sysfunc(libref(models)) %then %do;
    %let _models_path=&RES_PATH/models;
    %if %sysfunc(fileexist("&_models_path"))=0 %then %do; data _null_; rc=dcreate('models',"&RES_PATH"); run; %end;
    libname models "&_models_path";
  %end;
%mend; %ensure_models

%macro ensure_score;
  %if %sysfunc(libref(score)) %then %do;
    %let _score_path=&RES_PATH/score;
    %if %sysfunc(fileexist("&_score_path"))=0 %then %do; data _null_; rc=dcreate('score',"&RES_PATH"); run; %end;
    libname score "&_score_path";
  %end;
%mend; %ensure_score

/* Guardrails */
%macro assert(ds,msg);
  %if %sysfunc(exist(&ds))=0 %then %do; %put ERROR: &msg; %abort cancel; %end;
%mend;
%assert(models.logit_step_model, Missing model artifact MODELS.LOGIT_STEP_MODEL. Run 04_model.sas.)
/* If you prefer full model, change champion below */

/* 1) Champion selector (easy to swap) */
%let champion = logit_step_model;   /* or logit_full_model */

/* 2) Pick dataset to score: HOLD if exists, else DEV */
%macro pick_toscore;
  %global _toscore _tag;
  %if %sysfunc(exist(wrk.hold)) %then %do; %let _toscore=wrk.hold; %let _tag=hold; %end;
  %else %do; %let _toscore=wrk.dev; %let _tag=dev; %end;
%mend; %pick_toscore
%assert(&_toscore, No dataset to score. Ensure 03_clean.sas created WRK.DEV/WRK.HOLD.)

/* 3) Score PD using saved model (no refit) */
ods exclude none;
proc logistic inmodel=models.&champion noprint;
  score data=&_toscore
        out=score.&_tag._scored_raw
        outroc=score.&_tag._roc
        fitstat;
run;

/* Standardize PD column name (P_1 => PD) */
data score.&_tag._scored;
  set score.&_tag._scored_raw;
  length PD 8;
  /* P_1 is the predicted prob for event='1' from PROC LOGISTIC */
  PD = coalesce(P_1, PredProb);  /* fallbacks if version differs */
run;

/* 4) Find Youden-J optimal cut on the scored set’s ROC */
proc sql noprint;
  select _PROB_ into :cut_youden
  from score.&_tag._roc
  having (_SENSIT_ - _1MSPEC_) = max((_SENSIT_ - _1MSPEC_));
quit;

/* 5) Add classifications at 0.5 and Youden-J */
data score.&_tag._scored;
  set score.&_tag._scored;
  length pred_05 pred_yj 3;
  pred_05 = (PD >= 0.5);
  pred_yj = (PD >= &cut_youden);
run;

/* 6) Convert PD → Points (BaseScore/BaseOdds/PDO) */
%let BaseScore = 600;    /* score at BaseOdds */
%let BaseOdds  = 50;     /* odds = non-default : default at BaseScore */
%let PDO       = 20;     /* points to double the odds */

data score.&_tag._scored;
  set score.&_tag._scored;
  length Points 8;
  if 0 < PD < 1 then do;
    odds   = (1-PD)/PD;
    Points = &BaseScore + (&PDO/log(2)) * ( log(odds) - log(&BaseOdds) );
  end;
  else Points = .;
  drop odds;
run;

/* 7) Small summary for the marker (optional) */
proc means data=score.&_tag._scored n mean min p25 p50 p75 max maxdec=3;
  var PD Points;
  title "Scoring summary (&_tag.) — PD and Points";
run; title;
