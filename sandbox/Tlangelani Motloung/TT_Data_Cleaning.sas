
/**************************************************/
/* Import the data from the provided Excel file */
/**************************************************/

FILENAME REFFILE '/export/viya/homes/37293168@mynwu.ac.za/BWIN 621 Assignment 1/data/raw/SmallBusinessLoans.xlsx';

PROC IMPORT DATAFILE=REFFILE
	DBMS=XLSX
	OUT=loans_data;
	GETNAMES=YES;
RUN;

/**************************************************/
/* Clean and modify the date to be able to use it */
/**************************************************/

data loans_clean;
    set loans_data;
    
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
