/* =========================
   Adapted from sas/02_eda.sas (BWIN621 Assignment 1 EDA)
   Original author: Tafara Kanyemba
   Adaptation: raw.loans (from an Excel LIBNAME import in the original
   script) is replaced by an inline sample of 30 rows with the same 19
   columns as the repo's SmallBusinessLoans.xlsx (Selected, LoanNr_ChkDgt,
   Name, Zip, Term, NoEmp, CreateJob, RetainedJob, FranchiseCode,
   UrbanRural, RevLineCr, DisbursementGross, BalanceGross, WrittenOff,
   New, RealEstate, Portion, Recession, Default). The derivation logic
   below is unchanged from the source script.
   ========================= */

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

/* ===== Build WORK.LOANS dataframe ===== */
data loans;
  set raw_loans;

  /* --- normalize a few fields to text for easy comparisons --- */
  length area $10
         default_txt rec_txt rev_txt re_txt ur_txt $12
         fc_txt $12;
  default_txt = upcase(strip(cats(Default)));
  rec_txt     = upcase(strip(cats(Recession)));
  rev_txt     = upcase(strip(cats(RevLineCr)));
  re_txt      = upcase(strip(cats(RealEstate)));
  ur_txt      = upcase(strip(cats(UrbanRural)));
  fc_txt      = strip(cats(FranchiseCode));

  /* --- Area --- */
  if ur_txt in ('URBAN','U','1') then area='Urban';
  else if ur_txt in ('RURAL','R','2') then area='Rural';
  else area='Undefined';

  /* --- Binary flags (0/1) --- */
  if default_txt in ('1','Y','YES','T','TRUE') then default_n=1;
  else if default_txt in ('0','N','NO','F','FALSE') then default_n=0;
  else default_n=.;

  if rec_txt in ('1','Y','YES','T','TRUE') then recession_n=1;
  else if rec_txt in ('0','N','NO','F','FALSE') then recession_n=0;
  else recession_n=.;

  if rev_txt in ('1','Y','YES','T','TRUE') then rev_n=1;
  else if rev_txt in ('0','N','NO','F','FALSE') then rev_n=0;
  else rev_n=.;

  if re_txt in ('1','Y','YES','T','TRUE') then re_n=1;
  else if re_txt in ('0','N','NO','F','FALSE') then re_n=0;
  else re_n=.;

  /* --- Franchise: <=1 => 0; >1 => 1 (treat blank as missing) --- */
  if fc_txt in ('', '.') then franchise=.;
  else if fc_txt in ('0','1') then franchise=0;
  else franchise=1;

  /* --- Numeric copies (assumes import created numeric vars) --- */
  disb          = DisbursementGross;   /* currency amount */
  p             = Portion;             /* 0-1 or 0-100 */
  if not missing(p) and p>1 then p=p/100;

  term_n        = Term;
  noemp_n       = NoEmp;
  createjob_n   = CreateJob;
  retainedjob_n = RetainedJob;

  drop default_txt rec_txt rev_txt re_txt ur_txt fc_txt;
run;

/* ===== 3) Defaults by Area ===== */
title "Defaults by Area";
proc freq data=loans; tables area*default_n / norow nocol nopercent; run;

title "Default Rate by Area";
proc means data=loans mean n maxdec=2;
  class area;
  var default_n;
  format default_n percent8.2; /* shows mean of 0/1 as a % */
run;
title;

/* ===== 4) Recession vs Not ===== */
title "Counts by Recession Status";
proc freq data=loans; tables recession_n / missing; run;

title "Default Rate by Recession Status";
proc means data=loans mean maxdec=2;
  class recession_n;
  var default_n;
  format default_n percent8.2;
run;
title;

/* ===== 5) Franchise vs Non-Franchise (FC rule) ===== */
data fr_rate;
  set loans(keep=default_n FranchiseCode);
  fc = inputn(cats(FranchiseCode),'best32.');
  if not missing(fc) then fr = (fc>1);  /* 0/1 */
  if nmiss(fr, default_n)=0;
run;

title "Defaults Summary by Franchise Status";
proc means data=fr_rate n mean sum maxdec=2;
  class fr; var default_n;
run;

proc freq data=fr_rate;
  tables fr*default_n / chisq;
  exact fisher;
run;

/* ===== 6) Disbursement by Default ===== */
title "Average Disbursement Gross by Default Status";
proc means data=loans mean n maxdec=2;
  class default_n;
  var disb;
  format disb dollar12.;
run;
title;

/* ===== 9) Credit structure cross-tab ===== */
title "RevLineCr x RealEstate";
proc freq data=loans; tables rev_n*re_n / missing; run;
title;
