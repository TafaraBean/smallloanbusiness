/* ==========================================================
   BWIN621 – Assignment 2
   Role A: Audit OOS & OOT (no cleaning, no transforms)
   Owner: Tafara
   ========================================================== */

/* 0) Project roots & create folders */
%let PROJ_ROOT=/export/viya/homes/41180569@mynwu.ac.za/BWIN621_Assignment_1/Assignment_2;

data _null_;
  length root $300;
  root = symget('PROJ_ROOT');
  rc1 = dcreate('sasdata', root);
  rc2 = dcreate('output',  root);
  rc3 = dcreate('tables',  cats(root,'/output'));
run;

/* Libraries */
libname here "&PROJ_ROOT/sasdata";

/* 1) IMPORT Excel (first worksheet of each file) */
proc import datafile="&PROJ_ROOT/data/raw/SmallBusinessLoans_OOS.xlsx"
    out=here.oos_raw dbms=xlsx replace;
    getnames=yes;
run;

proc import datafile="&PROJ_ROOT/data/raw/SmallBusinessLoans_OOT.xlsx"
    out=here.oot_raw dbms=xlsx replace;
    getnames=yes;
run;

/* 2) Add bad_flag (for prevalence) but NO other changes */
data here.oos_raw;
  set here.oos_raw;
  bad_flag = (Default=1);
run;

data here.oot_raw;
  set here.oot_raw;
  bad_flag = (Default=1);
run;

/* 3) Audited counts & prevalence */
proc sql;
  create table work._counts_oos as
  select count(*) as N,
         mean(bad_flag) as prevalence format=percent8.2
  from here.oos_raw;

  create table work._counts_oot as
  select count(*) as N,
         mean(bad_flag) as prevalence format=percent8.2
  from here.oot_raw;
quit;

proc export data=work._counts_oos
  outfile="&PROJ_ROOT/output/tables/00_counts_oos.csv" dbms=csv replace; run;

proc export data=work._counts_oot
  outfile="&PROJ_ROOT/output/tables/00_counts_oot.csv" dbms=csv replace; run;

/* 4) Data dictionary with missingness */

/* Variable list from OOS */
proc contents data=here.oos_raw out=work._dict_oos(keep=name type length) noprint; run;

/* Missingness OOS */
data work._long_oos;
  set here.oos_raw;
  length var $32 ismiss 8;
  array nums _numeric_;
  do i=1 to dim(nums);
    var = vname(nums[i]); ismiss = missing(nums[i]); output;
  end;
  array chrs _character_;
  do j=1 to dim(chrs);
    var = vname(chrs[j]); ismiss = (missing(chrs[j])); output;
  end;
  keep var ismiss;
run;

proc sql noprint; select count(*) into :_n_oos from here.oos_raw; quit;

proc sql;
  create table work._miss_oos as
  select var as name,
         sum(ismiss) as nmiss_oos,
         calculated nmiss_oos / max(1,&_n_oos) as pctmiss_oos format=percent8.2
  from work._long_oos
  group by var
  order by var;
quit;

/* Missingness OOT */
data work._long_oot;
  set here.oot_raw;
  length var $32 ismiss 8;
  array nums _numeric_;
  do i=1 to dim(nums);
    var = vname(nums[i]); ismiss = missing(nums[i]); output;
  end;
  array chrs _character_;
  do j=1 to dim(chrs);
    var = vname(chrs[j]); ismiss = (missing(chrs[j])); output;
  end;
  keep var ismiss;
run;

proc sql noprint; select count(*) into :_n_oot from here.oot_raw; quit;

proc sql;
  create table work._miss_oot as
  select var as name,
         sum(ismiss) as nmiss_oot,
         calculated nmiss_oot / max(1,&_n_oot) as pctmiss_oot format=percent8.2
  from work._long_oot
  group by var
  order by var;
quit;

/* Combine dictionary + missingness */
proc sql;
  create table work.data_dictionary as
  select a.name,
         case when a.type=1 then 'Numeric'
              when a.type=2 then 'Character'
              else 'Other' end as var_type,
         coalesce(b.nmiss_oos,0) as nmiss_oos,
         coalesce(b.pctmiss_oos,0) as pctmiss_oos format=percent8.2,
         coalesce(c.nmiss_oot,0) as nmiss_oot,
         coalesce(c.pctmiss_oot,0) as pctmiss_oot format=percent8.2
  from work._dict_oos a
  left join work._miss_oos b on a.name=b.name
  left join work._miss_oot c on a.name=c.name
  order by a.name;
quit;

proc export data=work.data_dictionary
  outfile="&PROJ_ROOT/output/tables/00_data_dictionary.csv" dbms=csv replace; run;

/* 5) Sanity prints */
title "Audited Counts OOS"; proc print data=work._counts_oos; run;
title "Audited Counts OOT"; proc print data=work._counts_oot; run;
title "Data Dictionary (first 20 rows)"; proc print data=work.data_dictionary(obs=20); run;
title;
