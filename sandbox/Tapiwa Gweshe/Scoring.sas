/*===============================================================
  Sandbox_Scoring.sas — score existing models on testing table
  - Uses three files sitting in your sandbox folder:
      loans_clean_test.sas7bdat
      logit_full_model.sas7bdat
      logit_step_model.sas7bdat
  - Outputs PD_full, PD_step, PD_diff and Points_full, Points_step
===============================================================*/

/* 0) Point a libref at your sandbox folder (has spaces → keep quotes) */
%let SBX_DIR=/export/viya/homes/56129149@mynwu.ac.za/casuser/BWIN621_Assignment/sandbox/Tapiwa Gweshe;
libname sbx "&SBX_DIR";

/* 1) Guardrails */
%macro assert(ds,msg);
  %if %sysfunc(exist(&ds))=0 %then %do; %put ERROR: &msg; %abort cancel; %end;
%mend;
%assert(sbx.loans_clean_test , Missing testing set: &SBX_DIR/loans_clean_test.sas7bdat)
%assert(sbx.logit_full_model , Missing model: &SBX_DIR/logit_full_model.sas7bdat)
%assert(sbx.logit_step_model , Missing model: &SBX_DIR/logit_step_model.sas7bdat)

/* 2) Copy testing set and add a row id to merge scored outputs safely */
data sbx.test; 
  set sbx.loans_clean_test; 
  _rid_=_n_; 
run;

/* 3) Score PDs from saved models (no refit) */
proc logistic inmodel=sbx.logit_full_model noprint;
  score data=sbx.test 
        out=sbx._full_scored(keep=_rid_ Default P_1 rename=(P_1=PD_full))
        fitstat;
run;

proc logistic inmodel=sbx.logit_step_model noprint;
  score data=sbx.test 
        out=sbx._step_scored(keep=_rid_ Default P_1 rename=(P_1=PD_step))
        fitstat;
run;

/* 4) Merge and compute PD difference */
data sbx.test_scored;
  merge sbx._full_scored sbx._step_scored;
  by _rid_;
  PD_diff = PD_step - PD_full;
run;

/* 5) Convert PDs → credit points (BaseScore/BaseOdds/PDO) */
%let BaseScore = 600;   /* score at BaseOdds */
%let BaseOdds  = 50;    /* non-default : default at BaseScore */
%let PDO       = 20;    /* points to double the odds */

data sbx.test_scored;
  set sbx.test_scored;

  if 0<PD_full<1 then do;
    Points_full = &BaseScore + (&PDO/log(2))*( log((1-PD_full)/PD_full) - log(&BaseOdds) );
  end; else Points_full = .;

  if 0<PD_step<1 then do;
    Points_step = &BaseScore + (&PDO/log(2))*( log((1-PD_step)/PD_step) - log(&BaseOdds) );
  end; else Points_step = .;
run;

/* 6) Preview and simple summary so you see output */
title "Scored preview (first 15 rows) — PDs and Points";
proc print data=sbx.test_scored(obs=15) noobs;
  var Default PD_full PD_step PD_diff Points_full Points_step;
run;

title "Summary (PDs and Points)";
proc means data=sbx.test_scored n mean p25 p50 p75 min max maxdec=4;
  var PD_full PD_step PD_diff Points_full Points_step;
run;
title;

/* 7) If Default exists, show quick confusion @0.5 */
%macro confusion_if_default;
  %local dsid pos rc;
  %let dsid=%sysfunc(open(sbx.test_scored,i));
  %let pos=%sysfunc(varnum(&dsid,Default));
  %let rc=%sysfunc(close(&dsid));
  %if &pos>0 %then %do;
    proc format; value pred05 low-<0.5='0' 0.5-high='1'; run;

    title "Confusion (Full @0.5)";  
    proc freq data=sbx.test_scored; 
      tables Default*PD_full / norow nocol nopercent; 
      format PD_full pred05.; 
    run;

    title "Confusion (Step @0.5)";  
    proc freq data=sbx.test_scored; 
      tables Default*PD_step / norow nocol nopercent; 
      format PD_step pred05.; 
    run;
    title;
  %end;
%mend; 
%confusion_if_default
