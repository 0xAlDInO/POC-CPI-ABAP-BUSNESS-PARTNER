*&---------------------------------------------------------------------*
*& Include LZFG_BP_CONTACT_OO_TOP
*&---------------------------------------------------------------------*
*& Déclarations globales et définition de la classe locale pour l'OO
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

*&---------------------------------------------------------------------*
*& Class Definition: lcl_bp_contact_handler
*&---------------------------------------------------------------------*
CLASS lcl_bp_contact_handler DEFINITION FINAL.
  PUBLIC SECTION.
    METHODS:
      execute
        IMPORTING
          !iv_bp_parent      TYPE bu_partner
          !iv_first_name     TYPE bu_namep_f
          !iv_last_name      TYPE bu_namep_l
          !iv_bp_category    TYPE bu_type
          !iv_grouping       TYPE bu_group
          !iv_bp_role        TYPE bu_role
          !iv_date_from      TYPE dats
          !iv_date_to        TYPE dats
          !iv_street         TYPE ad_street
          !iv_house_number   TYPE ad_hsnm1
          !iv_postal_code    TYPE ad_pstcd1
          !iv_city           TYPE ad_city1
          !iv_country        TYPE land1
          !iv_region         TYPE regio
          !iv_language       TYPE spras
        EXPORTING
          !ev_bp_contact     TYPE bu_partner
          !ev_status_code    TYPE char10
          !ev_status_message TYPE bapi_msg
          !ct_return         TYPE ztt_bapiret2.

  PRIVATE SECTION.
    " Variables d'état (attributs d'instance) pour éviter de passer
    " de multiples variables de méthode en méthode.
    DATA: mv_bp_parent        TYPE bu_partner,
          mv_bp_contact       TYPE bu_partner,
          mv_bp_contact_bapi  TYPE bapibus1006_head-bpartner,
          mv_valid_from       TYPE but050-date_from,
          mv_valid_to         TYPE but050-date_to,
          mv_duplicate_id     TYPE bu_partner,
          mv_parent_lock_key  TYPE rstable-varkey,
          mv_status_code      TYPE char10,
          mv_status_message   TYPE bapi_msg,
          mt_return           TYPE ztt_bapiret2,
          ms_person_data      TYPE bapibus1006_central_person,
          ms_central_data     TYPE bapibus1006_central,
          ms_address_data     TYPE bapibus1006_address,
          mv_partnercategory  TYPE bu_type,
          mv_partnergroup     TYPE bu_group,
          mv_bp_role          TYPE bu_partnerrole.

    METHODS:
      validate_request
        IMPORTING
          !iv_bp_parent    TYPE bu_partner
          !iv_first_name   TYPE bu_namep_f
          !iv_last_name    TYPE bu_namep_l
          !iv_bp_category  TYPE bu_type
          !iv_street       TYPE ad_street
          !iv_house_number TYPE ad_hsnm1
          !iv_postal_code  TYPE ad_pstcd1
          !iv_city         TYPE ad_city1
          !iv_country      TYPE land1
          !iv_region       TYPE regio
        RETURNING
          VALUE(rv_ok)     TYPE abap_bool,

      resolve_validity
        IMPORTING
          !iv_date_from TYPE dats
          !iv_date_to   TYPE dats
        RETURNING
          VALUE(rv_ok)  TYPE abap_bool,

      check_parent_exists
        IMPORTING
          !iv_bp_parent_original TYPE bu_partner
        RETURNING
          VALUE(rv_ok)           TYPE abap_bool,

      lock_parent_creation
        RETURNING
          VALUE(rv_ok) TYPE abap_bool,

      find_duplicate_contact
        IMPORTING
          !iv_first_name TYPE bu_namep_f
          !iv_last_name  TYPE bu_namep_l,

      prepare_contact_data
        IMPORTING
          !iv_first_name   TYPE bu_namep_f
          !iv_last_name    TYPE bu_namep_l
          !iv_language     TYPE spras
          !iv_street       TYPE ad_street
          !iv_house_number TYPE ad_hsnm1
          !iv_postal_code  TYPE ad_pstcd1
          !iv_city         TYPE ad_city1
          !iv_country      TYPE land1
          !iv_region       TYPE regio
          !iv_bp_category  TYPE bu_type
          !iv_grouping     TYPE bu_group
          !iv_bp_role      TYPE bu_role,

      create_bp_person
        RETURNING
          VALUE(rv_ok) TYPE abap_bool,

      add_bp_role
        RETURNING
          VALUE(rv_ok) TYPE abap_bool,

      create_bp_relation
        RETURNING
          VALUE(rv_ok) TYPE abap_bool,

      commit_transaction
        IMPORTING
          !iv_bp_parent TYPE bu_partner
        RETURNING
          VALUE(rv_ok)  TYPE abap_bool,

      release_parent_lock,

      rollback_and_release,

      add_return
        IMPORTING
          !iv_type    TYPE bapiret2-type
          !iv_message TYPE any,

      set_error
        IMPORTING
          !iv_message TYPE any,

      evaluate_bapi_return
        IMPORTING
          !it_return_bapi TYPE bapiret2_tab
        RETURNING
          VALUE(rv_failed) TYPE abap_bool.
ENDCLASS.

" Inclusion du fichier d'implémentation de la classe locale
INCLUDE lzfg_bp_contact_oo_f01.
