CLASS zcl_abapgit_ci_test_repos DEFINITION
  PUBLIC
  CREATE PUBLIC .

  PUBLIC SECTION.
    INTERFACES:
      zif_abapgit_ci_repo_provider.

  PROTECTED SECTION.
  PRIVATE SECTION.
    METHODS:
      fetch_repo_page
        IMPORTING
          VALUE(iv_page_count) TYPE i
        RETURNING
          VALUE(rt_repos)      TYPE zif_abapgit_ci_definitions=>tty_repo
        RAISING
          zcx_abapgit_exception.

ENDCLASS.



CLASS zcl_abapgit_ci_test_repos IMPLEMENTATION.


  METHOD fetch_repo_page.

    DATA: li_http_client TYPE REF TO if_http_client,
          lv_rfcdes      TYPE rfcdes-rfcdest.

    lv_rfcdes = |API_GITHUB_{ sy-uname }|.

    SELECT SINGLE FROM rfcdes
           FIELDS rfcdest
           WHERE rfcdest = @lv_rfcdes
           INTO @lv_rfcdes.

    IF sy-subrc = 0.

      cl_http_client=>create_by_destination(
        EXPORTING
          destination              = lv_rfcdes
        IMPORTING
          client                   = li_http_client
        EXCEPTIONS
          argument_not_found       = 1
          destination_not_found    = 2
          destination_no_authority = 3
          plugin_not_active        = 4
          internal_error           = 5
          OTHERS                   = 6 ).

      IF sy-subrc <> 0.
        zcx_abapgit_exception=>raise_t100( ).
      ENDIF.

    ELSE.

      cl_http_client=>create_by_url(
        EXPORTING
          url                = 'https://api.github.com'
          ssl_id             = 'ANONYM'
        IMPORTING
          client             = li_http_client
        EXCEPTIONS
          argument_not_found = 1
          plugin_not_active  = 2
          internal_error     = 3
          OTHERS             = 4 ).

      IF sy-subrc <> 0.
        zcx_abapgit_exception=>raise_t100( ).
      ENDIF.

    ENDIF.

    DATA(lo_rest_client) = NEW cl_rest_http_client( li_http_client ).

    lo_rest_client->if_rest_client~create_request_entity( )->set_header_field(
        iv_name  = '~request_uri'
        iv_value = |/orgs/abapGit-tests/repos?page={ iv_page_count }| ).

    lo_rest_client->if_rest_client~get( ).

    DATA(lo_response) = lo_rest_client->if_rest_client~get_response_entity( ).

    DATA(lv_status) = lo_rest_client->if_rest_client~get_status( ).

    IF lv_status <> cl_rest_status_code=>gc_success_ok.
      zcx_abapgit_exception=>raise( |HTTP status code { lv_status } from api.github.com| ).
    ENDIF.

    /ui2/cl_json=>deserialize(
      EXPORTING
        json = lo_response->get_string_data( )
      CHANGING
        data = rt_repos ).

  ENDMETHOD.


  METHOD zif_abapgit_ci_repo_provider~get_repos.

    DATA: lt_repos TYPE zif_abapgit_ci_definitions=>tty_repo.

    DO.

      TRY.
          lt_repos = fetch_repo_page( iv_page_count = sy-index ).

        CATCH zcx_abapgit_exception cx_rest_client_exception INTO DATA(lx_error).
          zcx_abapgit_exception=>raise( iv_text     = lx_error->get_text( )
                                        ix_previous = lx_error ).
      ENDTRY.

      IF lines( lt_repos ) = 0.
        EXIT.
      ENDIF.

      INSERT LINES OF lt_repos INTO TABLE rt_repos.

    ENDDO.

    " skip because they call the UI.. .
    "
    DELETE rt_repos WHERE name = |CUS0|
                       or name = |ECATT| " https://github.com/larshp/abapGit/issues/2113
                       OR name = |SPRX| " https://github.com/larshp/abapGit/issues/87
                       OR name = |IEXT| " https://github.com/larshp/abapGit/issues/2044
                       OR name = |IDOC| " https://github.com/larshp/abapGit/issues/2044
                       OR name = |XINK| " https://github.com/larshp/abapGit/issues/2106
                       OR name = |SFSW| "https://github.com/larshp/abapGit/issues/2083
                       .

    " Skip because old testcase. abapGit indicates diff because migration to new format
    DELETE rt_repos WHERE name = |DDLX_old|.

    " Skip because of diffs due to component info not supported in NW752 dev edition
    DELETE rt_repos WHERE name = |DEVC_component|.


    SORT rt_repos BY name.

  ENDMETHOD.
ENDCLASS.
