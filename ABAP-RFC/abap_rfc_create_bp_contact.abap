*&---------------------------------------------------------------------*
*& Function Module : ZRFC_BP_CONTACT_EQ1
*& Remote-Enabled : Yes (SE37 > Attributes > Remote-Enabled Module)
*&---------------------------------------------------------------------*
*& Requires includes LZFG_BP_CONTACT_EQ1TOP and LZFG_BP_CONTACT_EQ1F01.
*& Create the interface below in SE37, then paste the implementation.
*&
*& IMPORTING
*&   IV_BP_PARENT   TYPE BU_PARTNER
*&   IV_FIRST_NAME  TYPE BU_NAMEP_F
*&   IV_LAST_NAME   TYPE BU_NAMEP_L
*&   IV_BP_CATEGORY TYPE BU_TYPE           DEFAULT '1'
*&   IV_GROUPING    TYPE BU_GROUP          DEFAULT 'ZC'
*&   IV_BP_ROLE     TYPE BU_PARTNERROLE    DEFAULT 'BUP001'
*&   IV_STREET      TYPE AD_STREET         OPTIONAL
*&   IV_HOUSE_NUMBER TYPE AD_HSNM1         OPTIONAL
*&   IV_POSTAL_CODE TYPE AD_PSTCD1         OPTIONAL
*&   IV_CITY        TYPE AD_CITY1          OPTIONAL
*&   IV_COUNTRY     TYPE LAND1             OPTIONAL
*&   IV_REGION      TYPE REGIO             OPTIONAL
*&   IV_LANGUAGE    TYPE SPRAS             OPTIONAL
*&   IV_DATE_FROM   TYPE DATS              OPTIONAL
*&   IV_DATE_TO     TYPE DATS              OPTIONAL
*& EXPORTING
*&   EV_BP_CONTACT    TYPE BU_PARTNER
*&   EV_STATUS_CODE   TYPE CHAR10
*&   EV_STATUS_MESSAGE TYPE BAPI_MSG
*& CHANGING
*&   CT_RETURN TYPE ZTT_BAPIRET2 OPTIONAL
*&---------------------------------------------------------------------*
FUNCTION zrfc_bp_contact_eq1.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     REFERENCE(IV_BP_PARENT) TYPE  BU_PARTNER
*"     REFERENCE(IV_FIRST_NAME) TYPE  BU_NAMEP_F
*"     REFERENCE(IV_LAST_NAME) TYPE  BU_NAMEP_L
*"     REFERENCE(IV_BP_CATEGORY) TYPE  BU_TYPE
*"     REFERENCE(IV_GROUPING) TYPE  BU_GROUP
*"     REFERENCE(IV_BP_ROLE) TYPE  BU_ROLE
*"     REFERENCE(IV_DATE_FROM) TYPE  DATS
*"     REFERENCE(IV_DATE_TO) TYPE  DATS
*"     REFERENCE(IV_STREET) TYPE  AD_STREET
*"     REFERENCE(IV_HOUSE_NUMBER) TYPE  AD_HSNM1
*"     REFERENCE(IV_POSTAL_CODE) TYPE  AD_PSTCD1
*"     REFERENCE(IV_CITY) TYPE  AD_CITY1
*"     REFERENCE(IV_COUNTRY) TYPE  LAND1
*"     REFERENCE(IV_REGION) TYPE  REGIO
*"     REFERENCE(IV_LANGUAGE) TYPE  SPRAS
*"  EXPORTING
*"     REFERENCE(EV_BP_CONTACT) TYPE  BU_PARTNER
*"     REFERENCE(EV_STATUS_CODE) TYPE  CHAR10
*"     REFERENCE(EV_STATUS_MESSAGE) TYPE  BAPI_MSG
*"  CHANGING
*"     REFERENCE(CT_RETURN) TYPE  ZTT_BAPIRET2
*"----------------------------------------------------------------------

  DATA: lv_bp_parent       TYPE bu_partner,
        lv_bp_contact      TYPE bu_partner,
        lv_bp_contact_bapi TYPE bapibus1006_head-bpartner,
        lv_valid_from      TYPE but050-date_from,
        lv_valid_to        TYPE but050-date_to,
        lv_duplicate_id    TYPE bu_partner,
        lv_error_msg       TYPE bapi_msg,
        lv_bapi_failed     TYPE abap_bool,
        lv_ok              TYPE abap_bool,
        lv_partnercategory TYPE bu_type,
        lv_partnergroup    TYPE bu_group,
        lv_bp_role         TYPE bu_partnerrole,
        lv_parent_lock_key TYPE rstable-varkey,
        ls_person_data     TYPE bapibus1006_central_person,
        ls_central_data    TYPE bapibus1006_central,
        ls_address_data    TYPE bapibus1006_address,
        ls_commit_return   TYPE bapiret2,
        lt_return_bapi     TYPE STANDARD TABLE OF bapiret2.

  CLEAR: ev_bp_contact, ev_status_code, ev_status_message, ct_return.

  PERFORM validate_request
    USING iv_bp_parent iv_first_name iv_last_name iv_bp_category
          iv_street iv_house_number iv_postal_code iv_city iv_country iv_region
    CHANGING lv_ok ev_status_code ev_status_message ct_return.
  IF lv_ok = abap_false.
    RETURN.
  ENDIF.

  PERFORM resolve_validity
    USING iv_date_from iv_date_to
    CHANGING lv_valid_from lv_valid_to lv_ok ev_status_code ev_status_message ct_return.
  IF lv_ok = abap_false.
    RETURN.
  ENDIF.

  CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
    EXPORTING
      input  = iv_bp_parent
    IMPORTING
      output = lv_bp_parent.

  PERFORM check_parent_exists
    USING lv_bp_parent iv_bp_parent
    CHANGING lv_ok ev_status_code ev_status_message ct_return.
  IF lv_ok = abap_false.
    RETURN.
  ENDIF.

  PERFORM lock_parent_creation
    USING lv_bp_parent
    CHANGING lv_parent_lock_key lv_ok ev_status_code ev_status_message ct_return.
  IF lv_ok = abap_false.
    RETURN.
  ENDIF.

  PERFORM find_duplicate_contact
    USING lv_bp_parent lv_valid_from lv_valid_to iv_first_name iv_last_name
    CHANGING lv_duplicate_id.
  IF lv_duplicate_id IS NOT INITIAL.
    PERFORM release_parent_lock USING lv_parent_lock_key.
    ev_bp_contact     = lv_duplicate_id.
    ev_status_code    = gc_status_exists.
    ev_status_message = |Le contact { lv_duplicate_id } existe déjà pour ce BP Parent.|.
    PERFORM add_return USING 'S' ev_status_message CHANGING ct_return.
    RETURN.
  ENDIF.

  PERFORM prepare_contact_data
    USING iv_first_name iv_last_name iv_language iv_street iv_house_number
          iv_postal_code iv_city iv_country iv_region iv_bp_category iv_grouping iv_bp_role
    CHANGING ls_person_data ls_central_data ls_address_data
             lv_partnercategory lv_partnergroup lv_bp_role.

  CALL FUNCTION 'BAPI_BUPA_CREATE_FROM_DATA'
    EXPORTING
      partnercategory   = lv_partnercategory
      partnergroup      = lv_partnergroup
      centraldata       = ls_central_data
      centraldataperson = ls_person_data
      addressdata       = ls_address_data
    IMPORTING
      businesspartner   = lv_bp_contact_bapi
    TABLES
      return            = lt_return_bapi.
  PERFORM evaluate_bapi_return
    TABLES lt_return_bapi
    CHANGING lv_bapi_failed lv_error_msg ct_return.
  IF lv_bapi_failed = abap_true.
    PERFORM rollback_and_release USING lv_parent_lock_key.
    lv_error_msg = |Erreur de création du BP : { lv_error_msg }|.
    PERFORM set_error
      USING lv_error_msg
      CHANGING ev_status_code ev_status_message ct_return.
    RETURN.
  ENDIF.

  lv_bp_contact = lv_bp_contact_bapi.
  ev_bp_contact = lv_bp_contact.
  IF lv_bp_contact IS INITIAL.
    PERFORM rollback_and_release USING lv_parent_lock_key.
    PERFORM set_error
      USING 'La création du BP n''a retourné aucun numéro de contact.'
      CHANGING ev_status_code ev_status_message ct_return.
    RETURN.
  ENDIF.

  CLEAR lt_return_bapi.
  CALL FUNCTION 'BAPI_BUPA_ROLE_ADD_2'
    EXPORTING
      businesspartner     = lv_bp_contact
      businesspartnerrole = lv_bp_role
    TABLES
      return              = lt_return_bapi.
  PERFORM evaluate_bapi_return
    TABLES lt_return_bapi
    CHANGING lv_bapi_failed lv_error_msg ct_return.
  IF lv_bapi_failed = abap_true.
    PERFORM rollback_and_release USING lv_parent_lock_key.
    lv_error_msg = |Erreur d'ajout du rôle : { lv_error_msg }|.
    PERFORM set_error
      USING lv_error_msg
      CHANGING ev_status_code ev_status_message ct_return.
    RETURN.
  ENDIF.

  CLEAR lt_return_bapi.
  CALL FUNCTION 'BAPI_BUPR_CONTP_CREATE'
    EXPORTING
      businesspartner = lv_bp_parent
      contactperson   = lv_bp_contact
      validfromdate   = lv_valid_from
      validuntildate  = lv_valid_to
    TABLES
      return          = lt_return_bapi.
  PERFORM evaluate_bapi_return
    TABLES lt_return_bapi
    CHANGING lv_bapi_failed lv_error_msg ct_return.
  IF lv_bapi_failed = abap_true.
    PERFORM rollback_and_release USING lv_parent_lock_key.
    lv_error_msg = |Erreur de création de la relation : { lv_error_msg }|.
    PERFORM set_error
      USING lv_error_msg
      CHANGING ev_status_code ev_status_message ct_return.
    RETURN.
  ENDIF.

  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
    EXPORTING
      wait = abap_true
    IMPORTING
      return = ls_commit_return.
  IF ls_commit_return-type IS NOT INITIAL OR ls_commit_return-message IS NOT INITIAL.
    APPEND ls_commit_return TO ct_return.
  ENDIF.
  PERFORM release_parent_lock USING lv_parent_lock_key.

  IF ls_commit_return-type = 'E' OR ls_commit_return-type = 'A'
     OR ls_commit_return-type = 'X'.
    CLEAR ev_bp_contact.
    lv_error_msg = |Erreur lors du commit : { ls_commit_return-message }|.
    PERFORM set_error
      USING lv_error_msg
      CHANGING ev_status_code ev_status_message ct_return.
    RETURN.
  ENDIF.

  ev_bp_contact     = lv_bp_contact.
  ev_status_code    = gc_status_success.
  ev_status_message = |Contact créé et rattaché au BP Parent { iv_bp_parent }.|.
  lv_error_msg      = |Contact BP { ev_bp_contact } créé et rattaché au BP Parent { iv_bp_parent }.|.
  PERFORM add_return
    USING 'S' lv_error_msg
    CHANGING ct_return.

ENDFUNCTION.
