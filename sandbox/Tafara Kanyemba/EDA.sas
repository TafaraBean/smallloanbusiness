/* ==================== Universal ingest + proportions + pies (3 areas) ==================== */
options mprint mlogic symbolgen;
ods graphics on;

/* --- 1) Repo root discovery (works across users) --- */
%macro set_proj_root(repo=BWIN621_Assignment_1);
  %global PROJ_ROOT;
  %let PROJ_ROOT=;
  %if %symexist(_SASPROGRAMFILE) and %length(&_SASPROGRAMFILE) %then %do;
    %let _pgm=&_SASPROGRAMFILE;
    %let pos=%index(&_pgm,&repo);
    %if &pos>0 %then %let PROJ_ROOT=%substr(&_pgm,1,%eval(&pos+%length(&repo)-1));
  %end;
  %if %length(&PROJ_ROOT)=0 %then %let PROJ_ROOT=%sysget(HOME)/&repo;
  %put NOTE: Using PROJ_ROOT=&PROJ_ROOT;
%mend;
%set_proj_root();

/* --- 2) Import first sheet of the workbook --- */
%let RAWFILE=&PROJ_ROOT/data/raw/SmallBusinessLoans.xlsx;
libname _xl xlsx "&RAWFILE";
proc sql noprint;
  select memname into :_sheet trimmed
  from dictionary.tables
  where libname='_XL' and memtype='DATA'
  order by memname;
quit;

data work.loans_raw; set _xl.&_sheet; run;
libname _xl clear;

/* --- 3) Normalize fields: area (Urban/Rural/Undefined) and Default_n (0/1) --- */
proc format;
  value $areaLbl 'Urban'='Urban' 'Rural'='Rural' 'Undefined'='Undefined';
  value defLbl   0='Non-Default' 1='Default';
run;

data work.loans_prep;
  set work.loans_raw;
  length area $10;

  /* Map UrbanRural robustly (handles char/numeric; 0/blank => Undefined) */
  if vtype(UrbanRural)='C' then do;
    _ur = upcase(strip(UrbanRural));
    if _ur in ('URBAN','U','1') then area='Urban';
    else if _ur in ('RURAL','R','2') then area='Rural';
    else area='Undefined';
  end;
  else do; /* numeric */
    if UrbanRural=1 then area='Urban';
    else if UrbanRural=2 then area='Rural';
    else area='Undefined';
  end;

  /* Default flag to 0/1 */
  if vtype(Default)='C' then do;
    _d = upcase(strip(Default));
    Default_n = (_d in ('1','Y','YES','TRUE','T'));
  end;
  else Default_n = (Default=1);

  format area $areaLbl. Default_n defLbl.;
  drop _ur _d;
run;

/* --- 4) Proportion of defaulters (all three areas) --- */
proc sql;
  create table work.prop_default as
  select area,
         mean(Default_n) as prop_default format=percent8.2,
         sum(Default_n)  as defaults,
         count(*)        as N
  from work.loans_prep
  group by area
  order by case area when 'Urban' then 1 when 'Rural' then 2 else 3 end;
quit;

title "Proportion of Defaulters by Area (Urban / Rural / Undefined)";
proc print data=work.prop_default noobs label;
  label prop_default='Default Rate' defaults='# Defaults' N='N';
run; title;

title "Counts of Defaults (0/1) by Area";
proc freq data=work.loans_prep;
  tables area*Default_n / nocol norow nopercent;
run; title;

/* --- 5) Pie charts: one per area (includes Undefined) ------------------- */
ods graphics / width=560px height=400px;

%macro pie(area);
title "Default vs Non-Default — &area";
proc sgpie data=work.loans_prep;
  where area="&area";
  pie Default_n /
       datalabeldisplay=(category percent)
       datalabelloc=inside
       startangle=90;
  format Default_n defLbl.;
run;
%mend;

%pie(Urban);
%pie(Rural);
%pie(Undefined);
title;

/* OPTIONAL: 3-up layout saved to results HTML
ods html path="&PROJ_ROOT./results"(url=none)
         file="default_pies_3up.html" style=HTMLBlue;
ods layout gridded columns=3 advance=table;
%pie(Urban); %pie(Rural); %pie(Undefined);
ods layout end; ods html close;
*/

/* ---------- Portion stats + Franchise boxplot (FranchiseCode: 0/1 = Non-Franchise) ---------- */

proc format; value yesnofmt 0='Non-Franchise' 1='Franchise'; run;

/* Build WORK.PORTION_PREP with portion_frac (0–1) + franchise_flag (0/1) */
%macro build_portion_prep(ds=work.loans_raw, out=work.portion_prep);
  %local dsid rc hasF hasFC;
  %let dsid=%sysfunc(open(&ds,i));
  %if &dsid %then %do;
    %let hasF  = %sysfunc(varnum(&dsid,Franchise));
    %let hasFC = %sysfunc(varnum(&dsid,FranchiseCode));
    %let rc=%sysfunc(close(&dsid));
  %end;
  %else %do; %put ERROR: Could not open &ds..; %return; %end;

  data &out;
    set &ds;
    length franchise_flag 8;

    /* ---- PRIORITY: FranchiseCode (0/1 => Non-Franchise; else Franchise) ---- */
    %if %sysevalf(&hasFC>0) %then %do;
      if vtype(FranchiseCode)='C' then do;
        _fc_num = input(compress(FranchiseCode,' '), best32.);
        if missing(_fc_num) then franchise_flag = .;
        else franchise_flag = (_fc_num not in (0,1));
      end;
      else franchise_flag = (FranchiseCode not in (0,1));
      drop _fc_num;
    %end;
    /* ---- Fallback: Franchise Y/N ---- */
    %else %if %sysevalf(&hasF>0) %then %do;
      if vtype(Franchise)='C' then
        franchise_flag = (upcase(strip(Franchise)) in ('Y','YES','1','T','TRUE'));
      else franchise_flag = (Franchise=1);
    %end;
    %else %do;
      franchise_flag = .; /* no franchise info available */
    %end;

    /* --- Normalise Portion to a fraction (0–1) --- */
    if vtype(Portion)='C' then portion_raw = input(compress(Portion,' %,'), best32.);
    else portion_raw = Portion;

    if not missing(portion_raw) then do;
      if portion_raw>1.001 then portion_frac = portion_raw/100;
      else portion_frac = portion_raw;
    end;

    format franchise_flag yesnofmt. portion_frac percent8.2;
  run;
%mend;

%build_portion_prep();

/* 1) Min / Average / Max of guarantor portions */
title "Guarantor Portion — Min / Average / Max";
proc sql;
  select min(portion_frac) format=percent8.2 as Min_Portion,
         mean(portion_frac) format=percent8.2 as Avg_Portion,
         max(portion_frac) format=percent8.2 as Max_Portion
  from work.portion_prep
  where not missing(portion_frac);
quit; title;

/* 2) Boxplot: Portion by Franchise vs Non-Franchise */
ods graphics / width=740px height=460px;
title "Guarantor Portion by Franchise Status (FranchiseCode rule: 0/1 = Non-Franchise)";
proc sgplot data=work.portion_prep;
  vbox portion_frac / category=franchise_flag;
  yaxis label="Guarantor Portion" values=(0 to 1 by 0.1) valuesformat=percent8.;
  xaxis label="Franchise Status";
run; title;


/* ---------- Prep: numeric Term (months) + Default_n (0/1) ---------- */
data work.loans_term;
  set work.loans_raw;

  /* Term to numeric months (handles char like '36' or '36 months') */
  if vtype(Term)='C' then term_n = input(compress(Term,,'kd'), best32.);
  else term_n = Term;

  /* Default to 0/1 robustly */
  if vtype(Default)='C' then do;
    _d = upcase(strip(Default));
    default_n = (_d in ('1','Y','YES','TRUE','T'));
  end;
  else default_n = (Default=1);
  drop _d;
run;

/* ---------- 1) Default RATE by exact loan term (months) ---------- */
proc sql;
  create table work.default_rate_by_term as
  select term_n,
         count(*)        as N,
         sum(default_n)  as defaults,
         mean(default_n) as default_rate
  from work.loans_term
  where not missing(term_n)
  group by term_n
  order by term_n;
quit;

ods graphics / width=860px height=480px;
title "Default Rate by Loan Term (months)";
proc sgplot data=work.default_rate_by_term;
  *series x=term_n y=default_rate / markers;
  loess  x=term_n y=default_rate / nomarkers smooth=0.3;  /* gentle smoother */
  yaxis label="Default Rate" valuesformat=percent8.1;
  xaxis label="Loan Term (months)" grid;
run; title;




/* ---------- 2b) Default RATE by 12-month bins (clean bars) ---------- */
data work.loans_term_bins;
  set work.loans_term;
  if not missing(term_n) then do;
    bin_start = 12*floor((term_n-1)/12)+1;     /* 1–12, 13–24, … */
    bin_end   = bin_start + 11;
    length term_bin $11;
    term_bin  = cats(put(bin_start,3.), '-', put(bin_end,3.));
  end;
run;

proc sql;
  create table work.default_rate_by_bin as
  select term_bin, min(bin_start) as _order,
         count(*)        as N,
         sum(default_n)  as defaults,
         mean(default_n) as default_rate
  from work.loans_term_bins
  where not missing(term_bin)
  group by term_bin
  order by _order;
quit;

title "Default Rate by Loan Term (12-month bins)";
proc sgplot data=work.default_rate_by_bin;
  vbarparm category=term_bin response=default_rate / datalabel;
  yaxis label="Default Rate" valuesformat=percent8.1;
  xaxis label="Loan Term (months, 12-month bins)";
run; title;



/* Make sure the three vars are numeric (handles character columns too) */
data work.jobs_bubble;
  set work.loans_prep;                    /* or work.loans_raw */
  if vtype(NoEmp)='C'        then noemp_n        = input(compress(NoEmp,,'kd'), best32.);
  else                             noemp_n        = NoEmp;

  if vtype(CreateJob)='C'    then createjob_n    = input(compress(CreateJob,,'kd'), best32.);
  else                             createjob_n    = CreateJob;

  if vtype(RetainedJob)='C'  then retainedjob_n  = input(compress(RetainedJob,,'kd'), best32.);
  else                             retainedjob_n  = RetainedJob;

  /* keep complete cases */
  if nmiss(noemp_n, createjob_n, retainedjob_n)=0;
run;

/* Bubble plot */
ods graphics / width=860px height=520px;
title "No. Employees vs Jobs Created (Bubble = Jobs Retained)";
proc sgplot data=work.jobs_bubble;
  bubble x=noemp_n y=createjob_n size=retainedjob_n /
         bradiusmin=4 bradiusmax=18 transparency=0.20
         group=area                     /* <- remove this if you don't want colors by area */
         name="b";
  xaxis label="NoEmp"   grid;
  yaxis label="CreateJob" grid;
  keylegend "b" / title="Bubble size = RetainedJob";
run; title;

/* Bubble plot grouped by Franchise vs Non-Franchise */
proc format; value fr 0='Non-Franchise' 1='Franchise'; run;

data work.jobs_bubble_fr;
  set work.portion_prep(keep=NoEmp CreateJob RetainedJob franchise_flag);
  noemp_n       = input(compress(vvalue(NoEmp),,'kd'), best32.);
  createjob_n   = input(compress(vvalue(CreateJob),,'kd'), best32.);
  retainedjob_n = input(compress(vvalue(RetainedJob),,'kd'), best32.);
  fr = franchise_flag;
  if nmiss(noemp_n, createjob_n, retainedjob_n, fr)=0;
  format fr fr.;
run;

ods graphics / width=860px height=520px;
title "No. Employees vs Jobs Created (Bubble = Jobs Retained)";
proc sgplot data=work.jobs_bubble_fr;
  bubble x=noemp_n y=createjob_n size=retainedjob_n /
         bradiusmin=4 bradiusmax=18 transparency=0.20
         group=fr name="b";
  xaxis label="NoEmp" grid;
  yaxis label="CreateJob" grid;
  keylegend "b" / title="Bubble size = RetainedJob";
run; title;


proc iml;
  use work.jobs_bubble;
  read all var {noemp_n createjob_n retainedjob_n} into X;
  close;

  C = corr(X);
  names = {"NoEmp" "CreateJobs" "RetainedJobs"};

  call heatmapcont(C) xvalues=names yvalues=names
       colorramp={blue white red} title="Correlation Heat Map";
quit;

/* Map Recession -> 0/1 and use existing Default_n from loans_prep */
proc format; value recfmt 0='Not in Recession' 1='In Recession'; run;

data work.loans_rec;
  set work.loans_prep;                 /* has Default_n already */
  if vtype(Recession)='C' then Recession_n = (upcase(strip(Recession)) in ('1','Y','YES','T','TRUE'));
  else                               Recession_n = (Recession=1);
  format Recession_n recfmt.;
run;

/* Table: counts (and rate) of defaults by recession status */
title "Defaults by Recession Status";
proc sql;
  select put(Recession_n,recfmt.) as Recession,
         sum(Default_n)           as Defaults,
         count(*)                 as N,
         mean(Default_n) format=percent8.2 as Default_Rate
  from work.loans_rec
  where not missing(Recession_n)
  group by Recession_n;
quit; title;


/* If you already have work.loans_rec from earlier (with Recession_n = 0/1): */
proc sql;
  select
    sum(Recession_n=1) as In_Recession      format=comma.,
    sum(Recession_n=0) as Not_In_Recession  format=comma.,
    sum(missing(Recession_n)) as Missing    format=comma.,
    count(*)                 as Total       format=comma.
  from work.loans_rec;
quit;

proc sql;
  select case(Recession_n) when 1 then 'In Recession' else 'Not in Recession' end as Recession,
         mean(Default_n) format=percent8.2 as Default_Rate
  from work.loans_rec
  where not missing(Recession_n)
  group by Recession_n;
quit;

/* Two pies: default rate within each recession class */
ods graphics / width=520px height=380px;

ods layout gridded columns=2 advance=table;

title "Default Rate — In Recession";
proc sgpie data=work.loans_rec;
  where Recession_n=1;
  pie Default_n / datalabeldisplay=(category percent)
                  datalabelloc=inside startangle=90;
  format Default_n defLbl.;
run;

title "Default Rate — Not in Recession";
proc sgpie data=work.loans_rec;
  where Recession_n=0;
  pie Default_n / datalabeldisplay=(category percent)
                  datalabelloc=inside startangle=90;
  format Default_n defLbl.;
run;

ods layout end;
title;


/* Map to 0/1 on the fly (works whether vars are char or numeric) */
proc format; value yn 0='No' 1='Yes'; run;

data rev_re;
  set work.loans_raw;                           /* or work.loans_prep */
  rev_n = (upcase(strip(vvalue(RevLineCr))) in ('1','Y','YES','T','TRUE'));
  re_n  = (upcase(strip(vvalue(RealEstate))) in ('1','Y','YES','T','TRUE'));
  format rev_n re_n yn.;
run;

/* One-way + two-way frequency table */
proc freq data=rev_re;
  tables rev_n re_n rev_n*re_n / missing;
run;

/* Franchise vs Non-franchise bars: mean Disbursement by Portion bin */
proc format; value fr 0='Non-Franchise' 1='Franchise'; run;

data d;
  set work.portion_prep(keep=DisbursementGross portion_frac franchise_flag);
  disb = inputn(vvalue(DisbursementGross),'dollar32.');
  pbin = round(portion_frac, 0.05);   /* 5% bins */
  fr   = franchise_flag;
  if nmiss(disb,pbin,fr)=0;
  format disb dollar12. pbin percent8.0 fr fr.;
run;

title "Mean Disbursement Gross by Portion (5% bins), Franchise vs Non-Franchise";
proc sgplot data=d;
  vbar pbin / response=disb stat=mean group=fr groupdisplay=cluster datalabel;
  yaxis label="Mean Disbursement Gross" valuesformat=dollar12.;
  xaxis label="Portion";
run;
title;


title "Average Disbursement Gross by Area";
proc sql;
  select area,
         mean( inputn(cats(DisbursementGross),'dollar32.') ) as Avg_Disbursement format=dollar12.,
         count(*) as N
  from work.loans_prep
  group by area
  order by case area when 'Urban' then 1 when 'Rural' then 2 else 3 end;
quit;
title;










