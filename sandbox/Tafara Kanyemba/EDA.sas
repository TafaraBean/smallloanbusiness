/* ===== 0) Libraries + import (drop-in) ===== */
%let PROJ_ROOT=/export/viya/homes/41180569@mynwu.ac.za/BWIN621_Assignment_1;   /* change if your path differs */
libname proj "&PROJ_ROOT";
libname raw  "&PROJ_ROOT/data/raw";

/* Read the first sheet of the Excel file into WORK.LOANS_RAW */
libname xl xlsx "&PROJ_ROOT/data/raw/SmallBusinessLoans.xlsx";
proc sql noprint;
  select memname into :sheet trimmed
  from dictionary.tables
  where libname='XL' and memtype='DATA'
  order by memname;
quit;
data work.loans_raw; set xl.&sheet; run;
libname xl clear;

/* ===== 0b) Build WORK.LOANS (simple, student-friendly) ===== */
proc format; 
  value def 0='Non-Default' 1='Default';
  value fr  0='Non-Franchise' 1='Franchise';
  value rec 0='Not in Recession' 1='In Recession';
run;

data loans; 
  set work.loans_raw;

  /* Area */
  length area $10;
  _ur = upcase(strip(vvalue(UrbanRural)));
  if _ur in ('URBAN','U','1') then area='Urban';
  else if _ur in ('RURAL','R','2') then area='Rural';
  else area='Undefined';

  /* Flags */
  default_n   = (upcase(strip(vvalue(Default)))   in ('1','Y','YES','T','TRUE'));
  recession_n = (upcase(strip(vvalue(Recession))) in ('1','Y','YES','T','TRUE'));
  rev_n       = (upcase(strip(vvalue(RevLineCr))) in ('1','Y','YES','T','TRUE'));
  re_n        = (upcase(strip(vvalue(RealEstate)))in ('1','Y','YES','T','TRUE'));

  /* FranchiseCode rule: <=1 => Non-Franchise (0), >1 => Franchise (1) */
  fc = inputn(cats(FranchiseCode),'best32.');
  if not missing(fc) then franchise = (fc>1);
  else franchise = .;

  /* Numeric copies used later */
  disb          = inputn(cats(DisbursementGross),'dollar32.');
  p             = inputn(cats(Portion),'percent32.');
  if missing(p) then do; p=inputn(cats(Portion),'comma32.'); if p>1 then p=p/100; end;
  term_n        = inputn(cats(Term),'best32.');
  noemp_n       = inputn(cats(NoEmp),'best32.');
  createjob_n   = inputn(cats(CreateJob),'best32.');
  retainedjob_n = inputn(cats(RetainedJob),'best32.');

  format default_n def. franchise fr. recession_n rec. disb dollar12. p percent8.2;
  drop _ur;
run;


/* ========= 1) Where are defaults happening? — by Area ========= */
title "Defaults by Area";
proc freq data=loans; tables area*default_n / norow nocol nopercent; run;

title "Default Rate by Area";
proc means data=loans mean n maxdec=2; class area; var default_n; format default_n percent8.2; run; title;

ods graphics / width=520px height=380px;
title "Default vs Non-Default — Urban";
proc sgpie data=loans(where=(area='Urban'));   pie default_n / datalabeldisplay=(category percent); run;
title "Default vs Non-Default — Rural";
proc sgpie data=loans(where=(area='Rural'));   pie default_n / datalabeldisplay=(category percent); run;
title "Default vs Non-Default — Undefined";
proc sgpie data=loans(where=(area='Undefined')); pie default_n / datalabeldisplay=(category percent); run; title;


/* ========= 2) Macro environment: Recession vs Not ========= */
title "Counts by Recession Status";
proc freq data=loans; tables recession_n / missing; run;

title "Default Rate by Recession Status";
proc means data=loans mean maxdec=2; class recession_n; var default_n; format default_n percent8.2; run; title;

ods graphics / width=520px height=380px;
title "Default Rate — In Recession";
proc sgpie data=loans(where=(recession_n=1)); pie default_n / datalabeldisplay=(category percent); run;
title "Default Rate — Not in Recession";
proc sgpie data=loans(where=(recession_n=0)); pie default_n / datalabeldisplay=(category percent); run; title;


/* ========= 3) Business model: Franchise vs Non-Franchise ========= */
/* FC ≤ 1 → Non-Franchise; >1 → Franchise */
proc format; value fr 0='Non-Franchise (FC≤1)' 1='Franchise (FC>1)'; run;

data fr_rate;
  set loans(keep=default_n FranchiseCode);
  fc = inputn(cats(FranchiseCode),'best32.');
  if not missing(fc) then fr = (fc>1);
  if nmiss(fr, default_n)=0;
run;

title "Default Rate by Franchise Status";
proc sgplot data=fr_rate;
  vbar fr / response=default_n stat=mean datalabel;
  yaxis label="Default Rate" valuesformat=percent8.1;
  xaxis label="Franchise Status";
  format fr fr.;
run; title;

title "Defaults Summary by Franchise Status";
proc means data=fr_rate n mean sum maxdec=2;
  class fr; var default_n; format fr fr.;
run;

proc freq data=fr_rate;
  tables fr*default_n / chisq;
  exact fisher;
run;


/* ========= 4) Money matters: Disbursement vs Default ========= */
title "Average Disbursement Gross by Default Status";
proc means data=loans mean n maxdec=2; 
  class default_n;
  var disb;                    /* numeric copy of DisbursementGross */
  format disb dollar12.;
run; title;


/* ========= 5) Time risk: Term length and default patterns ========= */
data loans_bins;
  set loans;
  if not missing(term_n) then term_bin = 12*floor((term_n-1)/12)+1;
  length term_lbl $11;
  if not missing(term_bin) then term_lbl=cats(put(term_bin,3.),'-',put(term_bin+11,3.));
run;

title "Default Rate by Loan Term (12-month bins)";
proc sgplot data=loans_bins;
  vbar term_lbl / response=default_n stat=mean datalabel;
  yaxis label="Default Rate" valuesformat=percent8.1;
  xaxis label="Loan Term (months)" discreteorder=data;
run; title;

/* Show bimodal term pattern among defaulters (simple density + histogram) */
title "Loan Term Distribution of Defaulted Loans (Histogram + Kernel)";
proc sgplot data=loans;
  where default_n=1 and not missing(term_n);
  histogram term_n / binwidth=12 scale=count transparency=0.2;
  density   term_n / type=kernel;
  xaxis label="Loan Term (months)" min=0 max=300;
  yaxis label="Defaults (count)";
run; title;


/* ========= 6) Operations view: Staffing vs Default segments ========= */
ods graphics / width=860px height=520px;
title "No. Employees vs Jobs Created — Defaulters (Bubble = Jobs Retained)";
proc sgplot data=loans(where=(default_n=1));
  bubble x=noemp_n y=createjob_n size=retainedjob_n / group=franchise transparency=0.2 bradiusmin=4 bradiusmax=18;
  xaxis label="NoEmp"; yaxis label="CreateJob";
run; title;

title "No. Employees vs Jobs Created — Non-Defaulters (Bubble = Jobs Retained)";
proc sgplot data=loans(where=(default_n=0));
  bubble x=noemp_n y=createjob_n size=retainedjob_n / group=franchise transparency=0.2 bradiusmin=4 bradiusmax=18;
  xaxis label="NoEmp"; yaxis label="CreateJob";
run; title;

title "Correlation Matrix (NoEmp, CreateJob, RetainedJob)";
proc corr data=loans plots=matrix(histogram);
  var noemp_n createjob_n retainedjob_n;
run; title;


/* ========= 7) Credit structure cross-tab (context) ========= */
title "RevLineCr × RealEstate";
proc freq data=loans; tables rev_n*re_n / missing; run; title;


/* ========= 8) (Optional appendix) Money by Portion & Franchise ========= */
data d2; set loans; pbin=round(p,0.05); if nmiss(disb,pbin,franchise)=0; format pbin percent8.; run;

title "Mean Disbursement Gross by Portion (5% bins), Franchise vs Non-Franchise";
proc sgplot data=d2;
  vbar pbin / response=disb stat=mean group=franchise groupdisplay=cluster datalabel;
  yaxis valuesformat=dollar12.; xaxis label="Portion";
run; title;

title "Mean Disbursement Gross by Portion (5% bins) — Defaulters Only";
proc sgplot data=d2(where=(default_n=1));
  vbar pbin / response=disb stat=mean group=franchise groupdisplay=cluster datalabel;
  yaxis valuesformat=dollar12.; xaxis label="Portion";
run; title;

title "Average Disbursement Gross by Area";
proc means data=loans mean n maxdec=2; class area; var disb; format disb dollar12.; run; title;
