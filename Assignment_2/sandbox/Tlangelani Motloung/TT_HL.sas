/******************************************/
/*							              */
/*       Hosmer-Lemeshow Test (HL)        */
/*	   						              */
/******************************************/


/*****************************************/
/* Model Development (Taken from Shahil) */
/*****************************************/

/*Import*/
filename REFFILE '/export/viya/homes/37293168@mynwu.ac.za/BWIN 621 Assignment 1/Assignment_2/sandbox/Tlangelani Motloung/SmallBusinessLoans.xlsx';
proc import datafile=REFFILE dbms=xlsx out=loans_data replace; getnames=yes; run;

/* Data Cleaning */
data loans_clean;
  set loans_data;
  if RevLineCr in ('Y','T') then RevLineCr_num=1; else RevLineCr_num=0;
  drop RevLineCr; rename RevLineCr_num=RevLineCr;
  if FranchiseCode<=1 then FranchiseCode=0; else FranchiseCode=1;
  drop Name LoanNr_ChkDgt Zip New WrittenOff BalanceGross;
run;

/* Reduced model */
proc logistic data=loans_clean(where=(Selected=1)) outmodel = logistic_model plots=none;
  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;
  model Default(event='1') =
        Term NoEmp CreateJob RetainedJob FranchiseCode
        UrbanRural RevLineCr DisbursementGross RealEstate
        Portion Recession
        / selection=stepwise slentry=0.05 slstay=0.05 lackfit;
run;
