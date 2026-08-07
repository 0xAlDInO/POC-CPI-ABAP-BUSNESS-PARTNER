*&---------------------------------------------------------------------*
*& Include LZFG_BP_CONTACT_EQ1TOP
*&---------------------------------------------------------------------*
*& Global declarations of function group ZFG_BP_CONTACT_EQ1.
*& Keep request-specific data local to the function module.
*&---------------------------------------------------------------------*

CONSTANTS: gc_status_success     TYPE char10             VALUE 'SUCCESS',
           gc_status_exists      TYPE char10             VALUE 'EXISTS',
           gc_status_locked      TYPE char10             VALUE 'LOCKED',
           gc_status_error       TYPE char10             VALUE 'ERROR',
           gc_bp_category_person TYPE bu_type            VALUE '1',
           gc_default_grouping   TYPE bu_group           VALUE 'ZC',
           gc_default_role       TYPE bu_partnerrole     VALUE 'BUP001',
           gc_contact_relation   TYPE but050-reltyp      VALUE 'BUR001',
           gc_date_to_infinite   TYPE but050-date_to     VALUE '99991231'.

" The generated UXX include is not editable. Load the FORM routines through
" the editable TOP include instead.
INCLUDE lzfg_bp_contact_eq1f01.
