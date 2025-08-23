/* ==================================
   BWIN621 Assignment 1 Data Cleaning 
   ================================== */

/* 1) Environment Bootstrap  */
%let _pgm=%sysfunc(dequote(&_SASPROGRAMFILE));
%let _dir=%substr(&_pgm,1,%eval(%length(&_pgm)-%length(%scan(&_pgm,-1,'/'))-1));
%include "&_dir/00_env.sas";
%if %sysfunc(exist(raw.loans))=0 %then %do; %include "&_dir/01_import.sas"; %end;

/* 2) Data Cleaning: Revolving Line credit and Franchise Code */
data wrk.loans_stage;
  set raw.loans;

  /* RevLineCr -> 0/1 (default unknowns to 0 = mode) */
  length _rev $12;
  _rev = upcase(strip(cats(RevLineCr)));
  if      _rev in ('1','Y','YES','T','TRUE') then RevLineCr_num=1;
  else if _rev in ('0','N','NO','F','FALSE') then RevLineCr_num=0;
  else                                        RevLineCr_num=0;
  drop RevLineCr _rev;
  rename RevLineCr_num=RevLineCr;

  /* FranchiseCode -> 0/1  (≤1 = Non-franchise; >1 = Franchise) */
  _fc = inputn(cats(FranchiseCode),'best32.');
  if missing(_fc) then FranchiseCode=.;
  else FranchiseCode = (_fc>1);
  drop _fc;

  /* Remove obvious IDs / admin fields (not for modelling) */
  drop Name LoanNr_ChkDgt Zip New WrittenOff BalanceGross;
run;

/* 3) Split for modelling (if Selected exists) */
%macro split_if_selected;
  %local dsid pos rc;
  %let dsid=%sysfunc(open(wrk.loans_stage,i));
  %let pos=%sysfunc(varnum(&dsid,Selected));
  %let rc=%sysfunc(close(&dsid));

  %if &pos>0 %then %do;
    data wrk.dev wrk.hold;
      set wrk.loans_stage;
      if Selected=1 then output wrk.dev; else output wrk.hold;
    run;
  %end;
  %else %do;
    data wrk.dev; set wrk.loans_stage; run;
  %end;
%mend; %split_if_selected

/* 4) Train/test aliases some teammates expect */
data wrk.loans_clean_train wrk.loans_clean_test;
  set wrk.loans_stage;
  if nmiss(Selected)=0 then do;
    if Selected=1 then output wrk.loans_clean_train;
    else               output wrk.loans_clean_test;
  end;
  else output wrk.loans_clean_train;  /* if no Selected, put all in train */
run;

/* 5) Quick visibility */
proc contents data=wrk.dev; title "WRK.DEV after cleaning"; run;
title;
