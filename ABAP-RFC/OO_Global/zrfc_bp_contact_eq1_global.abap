*&---------------------------------------------------------------------*
*& Function Module : ZRFC_BP_CONTACT_EQ1 (Version POO Globale - SE24)
*& Remote-Enabled : Yes (SE37 > Attributes > Remote-Enabled Module)
*&---------------------------------------------------------------------*
*& Instancie et appelle la classe globale SE24 ZCL_BP_CONTACT_HANDLER.
*&
*& IMPORTING
*&   VALUE(IV_BP_PARENT)   TYPE BU_PARTNER
*&   VALUE(IV_FIRST_NAME)  TYPE BU_NAMEP_F
*&   VALUE(IV_LAST_NAME)   TYPE BU_NAMEP_L
*&   VALUE(IV_BP_CATEGORY) TYPE BU_TYPE           DEFAULT '1'
*&   VALUE(IV_GROUPING)    TYPE BU_GROUP          DEFAULT 'ZC'
*&   VALUE(IV_BP_ROLE)     TYPE BU_PARTNERROLE    DEFAULT 'BUP001'
*&   VALUE(IV_STREET)      TYPE AD_STREET         OPTIONAL
*&   VALUE(IV_HOUSE_NUMBER) TYPE AD_HSNM1         OPTIONAL
*&   VALUE(IV_POSTAL_CODE) TYPE AD_PSTCD1         OPTIONAL
*&   VALUE(IV_CITY)        TYPE AD_CITY1          OPTIONAL
*&   VALUE(IV_COUNTRY)     TYPE LAND1             OPTIONAL
*&   VALUE(IV_REGION)      TYPE REGIO             OPTIONAL
*&   VALUE(IV_LANGUAGE)    TYPE SPRAS             OPTIONAL
*&   VALUE(IV_DATE_FROM)   TYPE DATS              OPTIONAL
*&   VALUE(IV_DATE_TO)     TYPE DATS              OPTIONAL
*& EXPORTING
*&   VALUE(EV_BP_CONTACT)    TYPE BU_PARTNER
*&   VALUE(EV_STATUS_CODE)   TYPE CHAR10
*&   VALUE(EV_STATUS_MESSAGE) TYPE BAPI_MSG
*& CHANGING
*&   VALUE(CT_RETURN) TYPE ZTT_BAPIRET2 OPTIONAL
*&---------------------------------------------------------------------*
FUNCTION zrfc_bp_contact_eq1.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_BP_PARENT) TYPE  BU_PARTNER
*"     VALUE(IV_FIRST_NAME) TYPE  BU_NAMEP_F
*"     VALUE(IV_LAST_NAME) TYPE  BU_NAMEP_L
*"     VALUE(IV_BP_CATEGORY) TYPE  BU_TYPE
*"     VALUE(IV_GROUPING) TYPE  BU_GROUP
*"     VALUE(IV_BP_ROLE) TYPE  BU_ROLE
*"     VALUE(IV_DATE_FROM) TYPE  DATS
*"     VALUE(IV_DATE_TO) TYPE  DATS
*"     VALUE(IV_STREET) TYPE  AD_STREET
*"     VALUE(IV_HOUSE_NUMBER) TYPE  AD_HSNM1
*"     VALUE(IV_POSTAL_CODE) TYPE  AD_PSTCD1
*"     VALUE(IV_CITY) TYPE  AD_CITY1
*"     VALUE(IV_COUNTRY) TYPE  LAND1
*"     VALUE(IV_REGION) TYPE  REGIO
*"     VALUE(IV_LANGUAGE) TYPE  SPRAS
*"  EXPORTING
*"     VALUE(EV_BP_CONTACT) TYPE  BU_PARTNER
*"     VALUE(EV_STATUS_CODE) TYPE  CHAR10
*"     VALUE(EV_STATUS_MESSAGE) TYPE  BAPI_MSG
*"  CHANGING
*"     VALUE(CT_RETURN) TYPE  ZTT_BAPIRET2
*"----------------------------------------------------------------------

  DATA lo_handler TYPE REF TO zcl_bp_contact_handler.

  CREATE OBJECT lo_handler.

  " Délégation complète du traitement à la classe globale SE24
  lo_handler->execute(
    EXPORTING
      iv_bp_parent      = iv_bp_parent
      iv_first_name     = iv_first_name
      iv_last_name      = iv_last_name
      iv_bp_category    = iv_bp_category
      iv_grouping       = iv_grouping
      iv_bp_role        = iv_bp_role
      iv_date_from      = iv_date_from
      iv_date_to        = iv_date_to
      iv_street         = iv_street
      iv_house_number   = iv_house_number
      iv_postal_code    = iv_postal_code
      iv_city           = iv_city
      iv_country        = iv_country
      iv_region         = iv_region
      iv_language       = iv_language
    IMPORTING
      ev_bp_contact     = ev_bp_contact
      ev_status_code    = ev_status_code
      ev_status_message = ev_status_message
      ct_return         = ct_return
  ).

ENDFUNCTION.
