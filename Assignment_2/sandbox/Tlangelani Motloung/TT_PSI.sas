/******************************************/
/*							              */
/*    Population Stability Index (PSI)    */
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
ods exclude all;
proc logistic data=loans_clean(where=(Selected=1)) outmodel = logistic_model plots=none;
  class UrbanRural RevLineCr RealEstate Recession FranchiseCode / param=ref;
  model Default(event='1') =
        Term NoEmp CreateJob RetainedJob FranchiseCode
        UrbanRural RevLineCr DisbursementGross RealEstate
        Portion Recession
        / selection=stepwise slentry=0.05 slstay=0.05;
run;
ods exclude none;



/********************************/
/* Scoring and Binning OOS data */
/********************************/


/*Import OOS dataset*/
filename file_OOS '/export/viya/homes/37293168@mynwu.ac.za/BWIN 621 Assignment 1/Assignment_2/sandbox/Tlangelani Motloung/SmallBusinessLoans_OOS.xlsx';
proc import datafile=file_OOS dbms=xlsx out=OOS replace; getnames=yes; run;

/* Data Cleaning */
data OOS;
  set OOS;
  if RevLineCr in ('Y','T') then RevLineCr_num=1; else RevLineCr_num=0;
  drop RevLineCr; rename RevLineCr_num=RevLineCr;
  if FranchiseCode<=1 then FranchiseCode=0; else FranchiseCode=1;
  drop Name LoanNr_ChkDgt Zip New WrittenOff;
run;

/* Scoring OOS */
proc logistic inmodel=logistic_model;
   score data = OOS out= OOS_Scored;
run;

/* Create bins for scored OOS */
data OOS_Scored_binned;
   set OOS_Scored;
   length score_bin $20;
   
   if P_1 < 0.1 then score_bin = "0-0.1";
   else if P_1 < 0.2 then score_bin = "0.1-0.2";
   else if P_1 < 0.3 then score_bin = "0.2-0.3";
   else if P_1 < 0.4 then score_bin = "0.3-0.4";
   else if P_1 < 0.5 then score_bin = "0.4-0.5";
   else if P_1 < 0.6 then score_bin = "0.5-0.6";
   else if P_1 < 0.7 then score_bin = "0.6-0.7";
   else if P_1 < 0.8 then score_bin = "0.7-0.8";
   else if P_1 < 0.9 then score_bin = "0.8-0.9";
   else score_bin = "0.9-1.0";
run;

/* Calculate distibution of binned OOS score */
proc freq data = OOS_Scored_binned noprint;
   tables score_bin / out= OOS_distribution;
run;

data OOS_distribution_pct;
   set OOS_distribution;
   expected_percentage = PERCENT / 100;
   keep score_bin count expected_percentage;
   rename count = expected_count;
run;


/********************************/
/* Scoring and Binning OOT data */
/********************************/

/* Importing OOT data */
filename file_OOT '/export/viya/homes/37293168@mynwu.ac.za/BWIN 621 Assignment 1/Assignment_2/sandbox/Tlangelani Motloung/SmallBusinessLoans_OOT.xlsx';
proc import datafile=file_OOT dbms=xlsx out=OOT replace; getnames=yes; run;

/* Data Cleaning */
data OOT;
  set OOT;
  if RevLineCr in ('Y','T') then RevLineCr_num=1; else RevLineCr_num=0;
  drop RevLineCr; rename RevLineCr_num=RevLineCr;
  if FranchiseCode<=1 then FranchiseCode=0; else FranchiseCode=1;
  drop Name LoanNr_ChkDgt Zip New WrittenOff;
run;

/* Scoring OOT */
proc logistic inmodel = logistic_model;
  score data = OOT out = OOT_Scored;
run;


/* Create bins for scored OOT */
data OOT_Scored_binned;
   set OOT_Scored;
   length score_bin $20;
   
   /* Create 10 equal bins from 0 to 1 */
   if P_1 < 0.1 then score_bin = "0-0.1";
   else if P_1 < 0.2 then score_bin = "0.1-0.2";
   else if P_1 < 0.3 then score_bin = "0.2-0.3";
   else if P_1 < 0.4 then score_bin = "0.3-0.4";
   else if P_1 < 0.5 then score_bin = "0.4-0.5";
   else if P_1 < 0.6 then score_bin = "0.5-0.6";
   else if P_1 < 0.7 then score_bin = "0.6-0.7";
   else if P_1 < 0.8 then score_bin = "0.7-0.8";
   else if P_1 < 0.9 then score_bin = "0.8-0.9";
   else score_bin = "0.9-1.0";
run;

/* Calculate distibution of binned OOT score */
proc freq data= OOT_Scored_binned noprint;
   tables score_bin / out=OOT_distribution;
run;

/* Calculate percentages */
data OOT_distribution_pct;
   set OOT_distribution;
   new_percentage = PERCENT / 100;  /* Convert to proportion */
   keep score_bin count new_percentage;
   rename count = new_count;
run;


/********************************/
/*        Calculating PSI       */
/********************************/


/* Create PSI table directly from the distribution datasets */
proc sql;
   create table psi_table as
   select 
      coalesce(train.score_bin, new.score_bin) as PD_Bins,
      train.expected_percentage as Base,
      new.new_percentage as Target,
      (train.expected_percentage - new.new_percentage) as Base_minus_Target,
      log(train.expected_percentage / new.new_percentage) as ln_Base_minus_ln_Target,
      ((train.expected_percentage - new.new_percentage) * 
       log(train.expected_percentage / new.new_percentage)) as Product
   from OOS_distribution_pct as train
   full join OOT_distribution_pct as new
   on train.score_bin = new.score_bin;
quit;

/* Calculate total PSI */
proc sql noprint;
   select sum(Product) into :total_psi
   from psi_table;
quit;

/* Display the final PSI table */
proc print data=psi_table noobs;
   title "Population Stability Index (PSI) for Default Probability Model";
   var PD_Bins Base Target Base_minus_Target ln_Base_minus_ln_Target Product;
   format Base Target Base_minus_Target 6.4 ln_Base_minus_ln_Target 6.4 Product 6.4;
run;

/* Add the total PSI line */
data _null_;
   file print;
   put "PSI = &total_psi";
run;







