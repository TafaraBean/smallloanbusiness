/* ==================================
   Adapted from sas/03_clean.sas (BWIN621 Assignment 1 Data Cleaning)
   Adaptation: raw.loans (from an Excel LIBNAME import in the original
   script) is replaced by an inline sample of the same 19 columns as
   the repo's SmallBusinessLoans.xlsx. The cleaning logic (RevLineCr
   recode, FranchiseCode binarize, ID-column drop, train/hold split)
   is unchanged from the source script.
   ================================== */

data raw_loans;
  infile datalines dlm='|' dsd missover;
  length Name $40 RevLineCr $1;
  input Selected LoanNr_ChkDgt Name $ Zip Term NoEmp CreateJob RetainedJob
        FranchiseCode UrbanRural RevLineCr $ DisbursementGross BalanceGross
        WrittenOff New RealEstate Portion Recession Default;
  datalines;
0|1899965010|Empire Realty Funding  Invest|90804|84|3|0|3|0|2|Y|5000|0|0|1|0|0.5|0|0
1|2432455000|Stricklys Inc.|91764|55|9|0|9|0|1|T|67328|0|34656|0|0|0.5|0|1
1|2743075001|PRIME RESIDENTIAL INVESTMENTS|95008|58|5|0|5|0|1|Y|124060|0|49592|0|0|0.5|0|1
1|6740524001|HOME ADVANTAGE CORP.|94544|240|4|4|0|1|1|N|936000|0|0|0|1|1|0|0
1|2629795001|MILLENNIUM ONE REALTY INC.|93010|72|7|5|7|0|1|N|100000|0|94526|0|0|0.5|0|1
0|7119444008|ROBINSON AND STEINBERG INC|92557|37|3|0|3|1|1|T|18000|0|12765|0|0|0.5|0|1
1|8594044010|GALAXY VIDEO  PHOTO INC|90405|60|1|0|1|1|1|Y|44076|0|0|0|0|0.5|0|0
0|2076795000|DANIEL REAL ESTATE  MORTGAGE|96080|56|1|2|1|0|1|N|20000|0|20000|1|0|0.5|0|1
0|7662174001|KEITH HARRIER PRODUCTION SERVI|90038|77|2|3|5|1|2|Y|145225|0|0|0|0|0.5|0|0
1|1115215000|First Step Funding Inc. dba F|92868|33|12|0|0|1|1|N|50000|0|38832|0|0|0.5|0|1
0|3021666000|TR AND ASSOCIATES INC|93004|84|1|0|1|1|1|Y|148180|0|0|0|0|0.5|0|0
0|1122875008|Patty Schwartzkopf Properties|93546|84|2|0|0|1|2|Y|11000|0|0|0|0|0.5|0|0
1|9165874008|CARDINAL  GOLD REAL ESTATE SE|90240|240|5|65|0|1|1|0|1152000|0|0|0|1|1|0|0
1|2155214003|SDSB ENTERTAINMENT GROUP INC A|93232|60|4|0|0|1|0|0|29000|0|0|0|0|0.5|0|0
0|3740825000|Star Way Productions Inc.|92562|300|1|9|0|0|1|N|632100|0|0|1|1|0.9|0|0
0|3020216003|EDWARD EREDIA INVESTMENTS|91732|51|4|0|4|1|1|Y|70000|0|29181|0|0|0.5|0|1
1|1802786005|PROPERTY APPRAISALS|94403|35|4|0|4|1|1|Y|26582|0|6651|0|0|0.5|1|1
0|4759403005|HITECH 1HOUR PHOTO  VIDEO|90024|273|4|0|0|1|0|N|320000|0|0|1|1|0.85|0|0
0|7456354006|SUSAN DAVID|90028|300|1|0|0|1|1|0|480200|0|0|1|1|0.75|0|0
1|1063815000|California Percussion LLC|94080|84|3|0|0|1|1|Y|25530|0|0|0|0|0.5|0|0
0|1592465008|Caruthers Valuation Group Inc|92408|46|5|0|5|0|1|Y|133922|0|49000|0|0|0.5|0|1
0|5748063009|UPTOWN VIDEO|95366|300|6|0|0|1|0|N|286800|0|0|0|1|0.85|0|0
0|2736755006|Frank Real Estate|90010|45|0|0|0|0|1|N|10000|0|7209|1|0|0.85|0|1
0|7545734004|HAN KOOK VIDEO RENTAL|95051|60|2|0|2|1|1|0|60000|0|0|0|0|0.5|0|0
1|4892334003|EZ RENTALS CENTER|91763|120|23|0|23|1|1|0|250000|0|0|0|0|0.75|0|0
0|2672275004|LOU ANDREW MANAGEMENT INC.|93060|53|2|1|3|0|1|Y|59667|0|24988|0|0|0.5|0|1
0|6461434006|IDEAL HOME CARE|90670|120|6|0|6|1|1|0|335000|0|0|0|0|0.75|0|0
1|1030805001|Global Parties Inc. dba Party|91360|64|6|0|0|1|1|Y|50000|0|47211|0|0|0.5|0|1
0|8799003006|WESTWOOD VIDEO|95521|85|4|0|0|1|0|N|18000|0|0|0|0|0.8|0|0
;
run;

/* 2) Data Cleaning: Revolving Line credit and Franchise Code */
data loans_stage;
  set raw_loans;

  /* RevLineCr -> 0/1 (default unknowns to 0 = mode) */
  length _rev $12;
  _rev = upcase(strip(cats(RevLineCr)));
  if      _rev in ('1','Y','YES','T','TRUE') then RevLineCr_num=1;
  else if _rev in ('0','N','NO','F','FALSE') then RevLineCr_num=0;
  else                                        RevLineCr_num=0;
  drop RevLineCr _rev;
  rename RevLineCr_num=RevLineCr;

  /* FranchiseCode -> 0/1  (<=1 = Non-franchise; >1 = Franchise) */
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
  %let dsid=%sysfunc(open(loans_stage,i));
  %let pos=%sysfunc(varnum(&dsid,Selected));
  %let rc=%sysfunc(close(&dsid));

  %if &pos>0 %then %do;
    data dev hold;
      set loans_stage;
      if Selected=1 then output dev; else output hold;
    run;
  %end;
  %else %do;
    data dev; set loans_stage; run;
  %end;
%mend; %split_if_selected

/* 4) Train/test aliases some teammates expect */
data loans_clean_train loans_clean_test;
  set loans_stage;
  if nmiss(Selected)=0 then do;
    if Selected=1 then output loans_clean_train;
    else               output loans_clean_test;
  end;
  else output loans_clean_train;  /* if no Selected, put all in train */
run;

/* 5) Quick visibility */
proc contents data=dev; title "DEV after cleaning"; run;
title;
