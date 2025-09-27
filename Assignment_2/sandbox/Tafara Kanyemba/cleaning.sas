/* ==================================
   BWIN621 Assignment 2 – Parity Prep
   Apply A1 cleaning to OOS & OOT
   ================================== */

%let PROJ_ROOT=/export/viya/homes/41180569@mynwu.ac.za/BWIN621_Assignment_1/Assignment_2;
libname here "&PROJ_ROOT/sasdata";

/* --- Apply A1 cleaning to OOS --- */
data here.oos_prep;
  set here.oos_raw;

  /* RevLineCr -> 0/1 (default unknowns to 0 = mode) */
  length _rev $12;
  _rev = upcase(strip(cats(RevLineCr)));
  if      _rev in ('1','Y','YES','T','TRUE') then RevLineCr_num=1;
  else if _rev in ('0','N','NO','F','FALSE') then RevLineCr_num=0;
  else                                        RevLineCr_num=0;
  drop RevLineCr _rev;
  rename RevLineCr_num=RevLineCr;

  /* FranchiseCode -> 0/1 (≤1 = Non-franchise; >1 = Franchise) */
  _fc = inputn(cats(FranchiseCode),'best32.');
  if missing(_fc) then FranchiseCode=.;
  else FranchiseCode = (_fc>1);
  drop _fc;

  /* Remove obvious IDs / admin fields */
  drop Name LoanNr_ChkDgt Zip New WrittenOff BalanceGross;
run;

/* --- Apply A1 cleaning to OOT --- */
data here.oot_prep;
  set here.oot_raw;

  /* RevLineCr -> 0/1 (default unknowns to 0 = mode) */
  length _rev $12;
  _rev = upcase(strip(cats(RevLineCr)));
  if      _rev in ('1','Y','YES','T','TRUE') then RevLineCr_num=1;
  else if _rev in ('0','N','NO','F','FALSE') then RevLineCr_num=0;
  else                                        RevLineCr_num=0;
  drop RevLineCr _rev;
  rename RevLineCr_num=RevLineCr;

  /* FranchiseCode -> 0/1 (≤1 = Non-franchise; >1 = Franchise) */
  _fc = inputn(cats(FranchiseCode),'best32.');
  if missing(_fc) then FranchiseCode=.;
  else FranchiseCode = (_fc>1);
  drop _fc;

  /* Remove obvious IDs / admin fields */
  drop Name LoanNr_ChkDgt Zip New WrittenOff BalanceGross;
run;

/* Quick sanity peek (optional) */
title "First 10 rows of OOS Prep"; proc print data=here.oos_prep(obs=10); run;
title "First 10 rows of OOT Prep"; proc print data=here.oot_prep(obs=10); run;
title;
