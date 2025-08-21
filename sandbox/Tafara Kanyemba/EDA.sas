/* =========================
   BWIN621 Assignment 1 EDA
   (No custom PROC FORMATs)
   ========================= */

/* Root folder (adjust if your path differs) */
%let PROJ_ROOT=/export/viya/homes/41180569@mynwu.ac.za/BWIN621_Assignment_1;

/* ===== 1) SIMPLE IMPORT (first worksheet) ===== */
proc import datafile="&PROJ_ROOT/data/raw/SmallBusinessLoans.xlsx"
    out=work.loans_raw
    dbms=xlsx
    replace;
    getnames=yes;   /* reads header row into variable names */
    /* (sheet=) omitted → imports FIRST sheet */
run;

/* ===== 2) Build WORK.LOANS with simple IF/ELSE cleaning ===== */
data loans;
  set work.loans_raw;

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

  /* --- Numeric copies (assumes PROC IMPORT made these numeric) --- */
  disb          = DisbursementGross;   /* currency amount */
  p             = Portion;             /* 0–1 or 0–100 */
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

ods graphics / width=520px height=380px;
title "Default vs Non-Default — Urban";
proc sgpie data=loans(where=(area='Urban'));
  pie default_n / datalabeldisplay=(category percent);
run;

title "Default vs Non-Default — Rural";
proc sgpie data=loans(where=(area='Rural'));
  pie default_n / datalabeldisplay=(category percent);
run;

title "Default vs Non-Default — Undefined";
proc sgpie data=loans(where=(area='Undefined'));
  pie default_n / datalabeldisplay=(category percent);
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

ods graphics / width=520px height=380px;
title "Default Rate — In Recession";
proc sgpie data=loans(where=(recession_n=1));
  pie default_n / datalabeldisplay=(category percent);
run;

title "Default Rate — Not in Recession";
proc sgpie data=loans(where=(recession_n=0));
  pie default_n / datalabeldisplay=(category percent);
run;
title;

/* ===== 5) Franchise vs Non-Franchise (FC rule) ===== */
data fr_rate;
  set loans(keep=default_n FranchiseCode);
  fc = inputn(cats(FranchiseCode),'best32.');
  if not missing(fc) then fr = (fc>1);  /* 0/1 */
  if nmiss(fr, default_n)=0;
run;

title "Default Rate by Franchise Status";
proc sgplot data=fr_rate;
  vbar fr / response=default_n stat=mean datalabel;  /* x-axis shows 0/1 */
  yaxis label="Default Rate" valuesformat=percent8.1;
  xaxis label="Franchise Status (0=Non, 1=Franchise)";
run;
title;

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

/* ===== 7) Loan Term effects ===== */
data loans_bins;
  set loans;
  if not missing(term_n) then term_bin = 12*floor((term_n-1)/12)+1; /* 1-12, 13-24, ... */
  length term_lbl $11;
  if not missing(term_bin) then term_lbl=cats(put(term_bin,3.),'-',put(term_bin+11,3.));
run;

title "Default Rate by Loan Term (12-month bins)";
proc sgplot data=loans_bins;
  vbar term_lbl / response=default_n stat=mean datalabel;
  yaxis label="Default Rate" valuesformat=percent8.1;
  xaxis label="Loan Term (months)" discreteorder=data;
run;
title;

title "Loan Term Distribution of Defaulted Loans (Histogram + Kernel)";
proc sgplot data=loans;
  where default_n=1 and not missing(term_n);
  histogram term_n / binwidth=12 scale=count transparency=0.2;
  density   term_n / type=kernel;
  xaxis label="Loan Term (months)" min=0 max=300;
  yaxis label="Defaults (count)";
run;
title;

/* ===== 8) Ops view: staffing vs jobs (bubbles) ===== */
ods graphics / width=860px height=520px;

title "No. Employees vs Jobs Created — Defaulters (Bubble = Jobs Retained)";
proc sgplot data=loans(where=(default_n=1));
  bubble x=noemp_n y=createjob_n size=retainedjob_n
         / group=franchise transparency=0.2 bradiusmin=4 bradiusmax=18;
  xaxis label="NoEmp"; yaxis label="CreateJob";
run;

title "No. Employees vs Jobs Created — Non-Defaulters (Bubble = Jobs Retained)";
proc sgplot data=loans(where=(default_n=0));
  bubble x=noemp_n y=createjob_n size=retainedjob_n
         / group=franchise transparency=0.2 bradiusmin=4 bradiusmax=18;
  xaxis label="NoEmp"; yaxis label="CreateJob";
run;
title;

/* Correlation among numeric staffing fields (defaults only) */
title "Correlation Matrix for Defaults (NoEmp, CreateJob, RetainedJob)";
proc corr data=loans(where=(default_n=1)) plots=matrix(histogram);
  var noemp_n createjob_n retainedjob_n;
run;

*There appears to be a negative and non-linear relationship;
title "Correlation Matrix for Defaults (NoEmp, DisbursementGross)";
proc corr data=loans(where=(default_n=1)) plots=matrix(histogram);
  var noemp_n disb; 
run;


title;

/* ===== 9) Credit structure cross-tab ===== */
title "RevLineCr × RealEstate";
proc freq data=loans; tables rev_n*re_n / missing; run;
title;

/* ===== 10) (Appendix) Disbursement by Portion & Franchise ===== */
data d2;
  set loans;
  pbin=round(p,0.05);                 /* 0%, 5%, 10%, ... */
  if nmiss(disb,pbin,franchise)=0;
  format pbin percent8.;              /* built-in, optional */
run;

title "Mean Disbursement Gross by Portion (5% bins), Franchise vs Non-Franchise";
proc sgplot data=d2;
  vbar pbin / response=disb stat=mean group=franchise groupdisplay=cluster datalabel;
  yaxis valuesformat=dollar12.; xaxis label="Portion";
run;

title "Average Disbursement Gross by Area";
proc means data=loans mean n maxdec=2;
  class area; var disb; format disb dollar12.;
run;
title;
