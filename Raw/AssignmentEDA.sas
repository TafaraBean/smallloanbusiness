/* Tell SAS it may create a new folder path when needed */
options dlcreatedir;

/* Root of your project (home directory is always there) */
%let proj = /home/u64134236/CRM Project;   /* adjust folder name if you like */

/* 3 persistent libraries – SAS will make the folders if missing */
libname raw "&proj./raw";
libname wrk "&proj./wrk";        /* cleaned / model-ready tables */
libname res "&proj./results";    /* all outputs land here        */

/* Link to the uploaded Excel file */
filename loans "&proj./raw/SmallBusinessLoans.xlsx";

/**********************************************************************
*  eda_full.sas  –  One-shot EDA visual pack (SAS OnDemand)
*---------------------------------------------------------------------
*  Outputs (PNG) land in:  /home/u64134236/CRM Project/results/plots/
**********************************************************************/

/*------------------------------ 0. ENVIRONMENT --------------------*/
%let proj = /home/u64134236/CRM Project;         /* <-- CHANGE to your real path */

libname raw "&proj./raw";
libname wrk "&proj./wrk";
libname res "&proj./results";

ods graphics / reset width=7in height=5in imagemap;
ods listing gpath="&proj./results/plots";

/*------------------------------ 1. IMPORT EXCEL -------------------*/
/* Skip import if the table already exists                          */
%macro import_if_needed;
   %if %sysfunc(exist(raw.loans))=0 %then %do;
       proc import datafile="&proj./raw/SmallBusinessLoans.xlsx"
                   out=raw.loans dbms=xlsx replace;
           sheet="Loa"; guesslng=32767;
       run;
   %end;
%mend;
%import_if_needed

/*------------------------------ 2. GLOBAL FORMATS -----------------*/
proc format;
    value ur_fmt 0='Undefined' 1='Urban' 2='Rural';
run;

/*------------------------------ 3. OVERALL DEFAULT BAR -----------*/
proc freq data=raw.loans noprint;
    tables Default / out=wrk.default_tot;
run;

data wrk.default_tot;
    set wrk.default_tot;
    length Status $10;
    Status = ifc(Default=1,'Defaulted','Paid');
    pct_lbl = cats(put(percent/100,percent8.0));
run;

ods graphics / imagename='Overall_Default_Rate';
proc sgplot data=wrk.default_tot;
    vbar Status / response=COUNT datalabel=pct_lbl datalabelposition=outside
                  fillattrs=(color=(_GREEN _RED));
    yaxis label='Count';
    title 'Loan Default Rate';
run;
ods graphics off;

/*------------------------------ 4. DEFAULT BY LOCATION -----------*/
proc freq data=raw.loans noprint;
    tables UrbanRural*Default / out=wrk.ur_def;
    format UrbanRural ur_fmt.;
run;

proc sql;
    create table wrk.ur_pct as
    select put(UrbanRural,ur_fmt.)               as Location length=12,
           Default,
           count                                 as n,
           calculated n / sum(n)                 as pct
    from   wrk.ur_def
    group  by UrbanRural;
quit;

ods graphics / imagename='Default_by_Location';
proc sgplot data=wrk.ur_pct;
    vbar  Location / response=pct group=Default groupdisplay=cluster
                     datalabel datalabelattrs=(size=7);
    yaxis label='Percentage' values=(0 to 1 by .2) valuesformat=percent8.;
    keylegend / title='Default';
    title 'Default Rate by Location Type';
run;
ods graphics off;

/*------------------------------ 5. DEFAULT BY FRANCHISE ----------*/
data wrk.fr_flag;
    set raw.loans;
    Franchise = (FranchiseCode > 1);
run;

proc freq data=wrk.fr_flag noprint;
    tables Franchise*Default / out=wrk.fr_tot;
run;

proc sql;
    create table wrk.fr_pct as
    select Franchise,
           Default,
           count                                 as n,
           calculated n / sum(n)                 as pct
    from   wrk.fr_tot
    group  by Franchise;
quit;

ods graphics / imagename='Default_by_Franchise';
proc sgplot data=wrk.fr_pct;
    vbar Franchise / response=pct group=Default groupdisplay=cluster
                     datalabel datalabelattrs=(size=7)
                     categoryorder=respdesc;
    yaxis label='Percentage' values=(0 to 1 by .2) valuesformat=percent8.;
    keylegend / title='Default';
    format Franchise 1='Franchise' 0='Non-Franchise';
    title 'Default Rate by Franchise Status';
run;
ods graphics off;

/*------------------------------ 6. TERM vs LOAN SIZE -------------*/
ods graphics / imagename='Term_vs_LoanSize';
proc sgplot data=raw.loans;
    scatter x=Term y=DisbursementGross / markerattrs=(color=blue symbol=circlefilled size=6);
    xaxis label='Term (months)';
    yaxis label='Loan Size ($)';
    title 'Term vs. Loan Size';
run;
ods graphics off;

/*------------------------------ 7. HISTOGRAMS + DENSITY ----------*/
/*   7.1 Build a macro variable NUM_LIST with all numeric vars      */
/*       (exclude obvious categoricals & IDs)                       */

proc sql noprint;
    select name
           into :num_list separated by ' '
    from   dictionary.columns
    where  libname='RAW'
      and  memname='LOANS'
      and  type='num'
      and  upcase(name) not in
           ( 'DEFAULT','URBANRURAL','SELECTED','FRANCHISECODE'
             'REVLINE','NEW','REALESTATE' );
quit;

/*   7.2 Loop & plot                                                */
%macro hist_all;
    %let k=%sysfunc(countw(&num_list));
    %do i=1 %to &k;
        %let v=%scan(&num_list,&i);

        ods graphics / imagename="Hist_&v";
        proc sgplot data=raw.loans;
            histogram &v / transparency=0.2 fillattrs=(color=gray);
            density   &v / lineattrs=(thickness=2);
            title "Histogram of data$&v";
        run;
        ods graphics off;
    %end;
%mend;
%hist_all

/*------------------------------ 8. WRAP UP -----------------------*/
title; footnote;
ods listing close;   /* ensure all plots are flushed to disk */

/*  Log reminder */
%put NOTE: All EDA plots saved to &proj./results/plots/ ;


