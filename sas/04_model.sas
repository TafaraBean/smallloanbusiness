/*===============================================================
  04_model.sas — fit logistic models and save artifacts
  - Tlangelani Motloung
===============================================================*/

/* 0) Bootstrap env */
%let _pgm=%sysfunc(dequote(&_SASPROGRAMFILE));
%let _dir=%substr(&_pgm,1,%eval(%length(&_pgm)-%length(%scan(&_pgm,-1,'/'))-1));
%include "&_dir/00_env.sas";
%if %sysfunc(exist(raw.loans))=0 %then %do; %include "&_dir/01_import.sas"; %end;
%if %sysfunc(exist(wrk.dev))=0 %then %do;   %include "&_dir/03_clean.sas";  %end;

/* 1) Ensure MODELS lib */
%macro ensure_models;
  %if %sysfunc(libref(models)) %then %do;
    %let _models_path=&RES_PATH/models;
    %if %sysfunc(fileexist("&_models_path"))=0 %then %do;
      data _null_; rc=dcreate('models',"&RES_PATH"); run;
    %end;
    libname models "&_models_path";
  %end;
%mend;
%ensure_models

/* 2) Guardrails */
%macro assert(ds,msg);
  %if %sysfunc(exist(&ds))=0 %then %do; %put ERROR: &msg; %abort cancel; %end;
%mend;
%assert(wrk.dev, WRK.DEV not available. Run 03_clean.sas first.)
%if %sysfunc(libref(models)) %then %do; %put ERROR: Libref MODELS not assigned.; %abort cancel; %end;

/* 3) Ensure predictors aligns with EDA/cleaning */
%let xlist = Term NoEmp CreateJob RetainedJob FranchiseCode
             UrbanRural RevLineCr RealEstate Recession
             DisbursementGross Portion;

/*====================== FULL MODEL =============================*/
ods exclude none;
ods output ParameterEstimates = models.full_params;

proc logistic data=wrk.dev desc outmodel=models.logit_full_model plots=none;
  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;
  model Default = &xlist;
  output out=wrk.dev_full_scored p=PD_full;
run;

/*====================== STEPWISE (REDUCED) =====================*/
ods output ParameterEstimates = models.step_params;

proc logistic data=wrk.dev desc outmodel=models.logit_step_model plots=none;
  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;
  model Default = &xlist / selection=stepwise slentry=0.05 slstay=0.05;
  output out=wrk.dev_step_scored p=PD_step;
run;
