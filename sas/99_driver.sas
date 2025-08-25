/*===============================================================
  99_driver.sas — end-to-end pipeline (import → clean → EDA → model)
===============================================================*/

/* A) Standard header (env + ensure import) */
%let _pgm = %sysfunc(dequote(&_SASPROGRAMFILE));
%let _dir = %substr(&_pgm,1,%eval(%length(&_pgm)-%length(%scan(&_pgm,-1,'/'))-1));
%include "&_dir/00_env.sas";
%if %sysfunc(exist(raw.loans))=0 %then %do; %include "&_dir/01_import.sas"; %end;

/* B) Run-id and plot folder */
%let run_id = %sysfunc(compress(%sysfunc(datetime(),e8601dt.),':-T '));
%let edadir = &RES_PATH/eda/&run_id;
%if %sysfunc(fileexist("&edadir"))=0 %then %do;
  data _null_; rc=dcreate("&run_id","&RES_PATH/eda"); run;
%end;
ods listing gpath="&edadir";

/* C) Safety assertions */
/*---------------------------------------------------------------
  %assert(ds, msg)
  Purpose: "Fail fast" guard. Stops the run if a required table
           does not exist.

  How it works:
    - %sysfunc(exist(&ds)) checks whether the two-level SAS data
      set &ds (e.g., WRK.DEV) exists. Returns 1 if found, 0 if not.
    - If 0, write a clear ERROR line to the log with &msg
      and abort the current program submission (%abort cancel)
      so downstream steps don’t run on a bad state.

  Example:
    %assert(raw.loans, RAW.LOANS not found even after import.)
----------------------------------------------------------------*/
%macro assert(ds, msg);
  %if %sysfunc(exist(&ds))=0 %then %do; %put ERROR: &msg; %abort cancel; %end;
%mend;

%macro assert(ds, msg);
  %if %sysfunc(exist(&ds))=0 %then %do; %put ERROR: &msg; %abort cancel; %end;
%mend;
%assert(raw.loans, RAW.LOANS not found even after import.)

/* D) CLEAN → EDA → MODEL → SCORE → VALIDATION (in that order) */
%include "&_dir/03_clean.sas";        /* writes WRK.DEV (and WRK.HOLD if present) */
%assert(wrk.dev, WRK.DEV not created by 03_clean.sas.)

%include "&_dir/02_eda.sas";          /* drops PNGs into &edadir */

%include "&_dir/04_model.sas";        /* fits logistic; writes wrk.dev_scored/roc, etc. */
%include "&_dir/05_score.sas";        /* scores hold-out if available */
%include "&_dir/06_validation.sas";   /* AUC/KS/decile-lift */

/* E) Final summary (handy for the marker) */
title "Project summary";
proc datasets lib=raw nolist;  contents data=_all_ out=_rawc(keep=memname nobs) noprint; quit;
proc datasets lib=wrk nolist;  contents data=_all_ out=_wrkc(keep=memname nobs) noprint; quit;

proc print data=_raw; title2 "RAW library tables"; run;
proc print data=_wrk; title2 "WRK library tables"; run;
title;
