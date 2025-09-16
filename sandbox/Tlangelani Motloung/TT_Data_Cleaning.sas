
/* Locate this program's folder and mount it as a libref */
%let _pgm=%sysfunc(dequote(&_SASPROGRAMFILE));
%let _dir=%substr(&_pgm,1,%eval(%length(&_pgm)-%length(%scan(&_pgm,-1,'/'))-1));
libname here "&_dir";

/* Change this if your file isn't named loans.sas7bdat */
%let INSET=loans;

/* Guard */
%macro assert(ds,msg);
  %if %sysfunc(exist(&ds))=0 %then %do; %put ERROR: &msg; %abort cancel; %end;
%mend;
%assert(here.&INSET, Expected dataset here.&INSET not found in &_dir)

/* ===== Data engineering  ===== */
data here.loans_stage;
  set here.&INSET;

  /* RevLineCr -> 0/1 (treat NULL/other as 0) */
  if RevLineCr in ('Y','T') then RevLineCr_num=1;
  else RevLineCr_num=0;
  drop RevLineCr;
  rename RevLineCr_num=RevLineCr;

  /* FranchiseCode -> binary */
  if FranchiseCode<=1 then FranchiseCode=0;
  else FranchiseCode=1;

  /* Drop obvious IDs / unused */
  drop Name LoanNr_ChkDgt Zip New WrittenOff BalanceGross;
run;

/* ===== Split: train/test using Selected if present ===== */
%macro split_if_selected;
  %local dsid pos rc;
  %let dsid=%sysfunc(open(here.loans_stage,i));
  %let pos=%sysfunc(varnum(&dsid,Selected));
  %let rc=%sysfunc(close(&dsid));

  %if &pos>0 %then %do;
    data here.loans_clean_train here.loans_clean_test;
      set here.loans_stage;
      if Selected=1 then output here.loans_clean_train;
      else output here.loans_clean_test;
    run;
    %put NOTE: Split done -> here.loans_clean_train (Selected=1), here.loans_clean_test (Selected=0).;
  %end;
  %else %do;
    data here.loans_clean_train; set here.loans_stage; run;
    data here.loans_clean_test;  set here.loans_stage(obs=0); run;  /* empty test */
    %put NOTE: Selected not found — train has all rows; test is empty.;
  %end;
%mend;
%split_if_selected

/* ===== Quick visibility ===== */
title "Structure after cleaning (here.loans_clean_train)";
proc contents data=here.loans_clean_train; run; title;

/* ===== Quick GLM on TEST set ===== */
proc glm data=here.loans_clean_test;
  class UrbanRural RevLineCr RealEstate Recession FranchiseCode;
  model Default = Term NoEmp CreateJob RetainedJob FranchiseCode
                  UrbanRural RevLineCr DisbursementGross RealEstate
                  Portion Recession;
  title 'Linear Regression for Default Prediction';
  output out=here.res_data r=resid p=pred;
run; quit;

proc univariate data=here.res_data normal;
  var resid; histogram resid; qqplot resid / normal(mu=est sigma=est);
run;

proc sgplot data=here.res_data;
  scatter x=pred y=resid;
  title 'Residuals vs Predictions (TEST set)';
run; title;

/* ===== Quick LOGISTIC on training set ===== */
proc logistic data=here.loans_clean_train;
  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;
  model Default(event='1') = Term NoEmp CreateJob RetainedJob FranchiseCode
                             UrbanRural RevLineCr DisbursementGross RealEstate
                             Portion Recession;
  title 'Logistic Regression for Default Prediction';
run; title;
