/*======================================================================
  TT_Data_Cleaning.sas  —  Data engineering refactor (env + import aware)
  - Uses project environment (00_env.sas) for libs/paths
  - Ensures RAW.LOANS is available via 01_import.sas
  - Applies TT’s transformations and outputs to WRK datasets
======================================================================*/

/* 1) Bootstrap environment (libs RAW/WRK/RES + CODE fileref) */
%include code("00_env.sas");   /* provided by 00_env.sas */

/* 2) Fetch RAW.LOANS from the import module if missing */
%macro ensure_import;
  %if %sysfunc(exist(raw.loans))=0 %then %do;
    %put NOTE: RAW.LOANS not found — invoking sas/01_import.sas ...;
    %include code("01_import.sas");
  %end;
%mend;
%ensure_import

/* 3) Data engineering shell: read RAW, write WRK  */
data wrk.loans_stage;
  set raw.loans;
    
    /* Recode RevLineCr */
	if RevLineCr = 'Y' then RevLineCr_num = 1;
	else if RevLineCr = 'T' then RevLineCr_num = 1;
	else if RevLineCr = 'N' then RevLineCr_num = 0;
	else RevLineCr_num = 0;
		
	drop RevLineCr; /* Drop the original character variable */
	rename RevLineCr_num = RevLineCr; 
	    
    /* Note:
    	Because  there are only 2 null values out of 2100, 
    	we believe that the assignment of the these values
    	will have very little impact. Hence, we have chosen
    	to assign zero(0), as this is the mode of the data
    */
   
    
    /* Recode FranchiseCode */
   if FranchiseCode <= 1 then FranchiseCode = 0;
   else FranchiseCode = 1;
    
    drop Name LoanNr_ChkDgt Zip New WrittenOff BalanceGross;
run;

/**************************************************/
/* Split the data into training and testing set */
/**************************************************/

data loans_clean_test loans_clean_train;
	set loans_clean;
	if selected = 1 then output loans_clean_train;
	else output loans_clean_test;
run;

/**************************************************/
/* Performing basic Linear and Logistic regression on test data*/
/**************************************************/

/* 4) Optional: split into development/hold-out if Selected exists */
%macro split_if_selected;
  %local dsid varnum rc;
  %let dsid  = %sysfunc(open(wrk.loans_stage,i));
  %let varnum= %sysfunc(varnum(&dsid,Selected));
  %let rc    = %sysfunc(close(&dsid));

  %if &varnum > 0 %then %do;
    data wrk.dev wrk.hold;
      set wrk.loans_stage;
      if Selected=1 then output wrk.dev;
      else output wrk.hold;
    run;
    %put NOTE: Split complete → WRK.DEV (Selected=1) and WRK.HOLD (Selected=0).;
  %end;
  %else %do;
    data wrk.dev; set wrk.loans_stage; run;
    %put NOTE: Variable Selected not found — using WRK.DEV only.;
  %end;
%mend;
%split_if_selected

/* 5) Quick visibility (safe to keep) */
proc contents data=wrk.dev;   title "WRK.DEV structure after TT cleaning"; run;

/* 1. Linear Regression */
proc glm data=loans_clean_test;
    class UrbanRural RevLineCr RealEstate Recession FranchiseCode;
    model Default = Term NoEmp CreateJob RetainedJob FranchiseCode 
                   UrbanRural RevLineCr DisbursementGross RealEstate 
                   Portion Recession ;
    title 'Linear Regression for Default Prediction';
    
    output out=res_data r=resid p=pred;
run;


/* Testing assumptions */
proc univariate data = res_data normal;
	var resid;
	hist resid;
	qqplot resid / normal(mu=est sigma=est);
run;

proc sgplot data = res_data;
	scatter x=pred y=resid;
	title 'Scatter Plot of resid vs pred';
run;




/* 2. Logistic Regression */
proc logistic data=loans_clean_test;
    class UrbanRural RevLineCr RealEstate Recession FranchiseCode;
    model Default(event='1') = Term NoEmp CreateJob RetainedJob FranchiseCode 
                              UrbanRural RevLineCr DisbursementGross RealEstate 
                              Portion Recession;
    title 'Logistic Regression for Default Prediction';
run;
