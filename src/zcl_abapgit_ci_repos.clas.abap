CLASS zcl_abapgit_ci_repos DEFINITION
  PUBLIC
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS:
      update_abapgit_repo
        RAISING
          zcx_abapgit_exception,

      update_abapgit_ci_repo
        RAISING
          zcx_abapgit_exception.

    METHODS:
      process_repos
        IMPORTING
          it_repos              TYPE zif_abapgit_ci_definitions=>tty_repo
        RETURNING
          VALUE(rt_result_list) TYPE zif_abapgit_ci_definitions=>ty_result-repo_result_list.

  PRIVATE SECTION.
    CLASS-METHODS:
      update_repo
        IMPORTING
          iv_repo_name TYPE string
        RAISING
          zcx_abapgit_exception,

      syntax_check
        IMPORTING
          iv_package TYPE devclass
        RAISING
          zcx_abapgit_exception.

    METHODS:
      process_repo
        CHANGING
          cs_ci_repo TYPE zabapgit_ci_result
        RAISING
          zcx_abapgit_exception.

ENDCLASS.

CLASS zcl_abapgit_ci_repos IMPLEMENTATION.

  METHOD process_repo.

    " You should remember that we process the repo in synchron RFC because of
    " shortdumps there doesn't crash the main process.

    cs_ci_repo-package = CONV devclass( |$___{ to_upper( cs_ci_repo-name ) }| ).

    CALL FUNCTION 'ZABAPGIT_CI_PROCESS_REPO'
      DESTINATION 'NONE'
      CHANGING
        cs_ci_repo            = cs_ci_repo
      EXCEPTIONS
        communication_failure = 1
        system_failure        = 2
        OTHERS                = 3.

    IF sy-subrc <> 0.
      cs_ci_repo-message = |Failure in ZABAPGIT_CI_PROCESS_REPO. Subrc = { sy-subrc } |.
      cs_ci_repo-status  = zif_abapgit_ci_definitions=>co_status-not_ok.
      RETURN.
    ENDIF.

  ENDMETHOD.


  METHOD process_repos.

    LOOP AT it_repos ASSIGNING FIELD-SYMBOL(<ls_repo>).

      INSERT CORRESPONDING #( <ls_repo> )
             INTO TABLE rt_result_list
             ASSIGNING FIELD-SYMBOL(<ls_ci_repo>).

      TRY.
          process_repo(
            CHANGING
              cs_ci_repo = <ls_ci_repo> ).

        CATCH zcx_abapgit_exception INTO DATA(lx_error).
          <ls_ci_repo>-status  = zif_abapgit_ci_definitions=>co_status-not_ok.
          <ls_ci_repo>-message = lx_error->get_text( ).
      ENDTRY.

      IF <ls_ci_repo>-create_package = zif_abapgit_ci_definitions=>co_status-not_ok
      OR <ls_ci_repo>-clone          = zif_abapgit_ci_definitions=>co_status-not_ok
      OR <ls_ci_repo>-pull           = zif_abapgit_ci_definitions=>co_status-not_ok
      OR <ls_ci_repo>-syntax_check   = zif_abapgit_ci_definitions=>co_status-not_ok
      OR <ls_ci_repo>-purge          = zif_abapgit_ci_definitions=>co_status-not_ok
      OR <ls_ci_repo>-status         = zif_abapgit_ci_definitions=>co_status-not_ok.

        <ls_ci_repo>-status = zif_abapgit_ci_definitions=>co_status-not_ok.

      ELSE.

        <ls_ci_repo>-status = zif_abapgit_ci_definitions=>co_status-ok.

      ENDIF.

    ENDLOOP.

  ENDMETHOD.


  METHOD update_abapgit_repo.

    update_repo( 'abapGit' ).

  ENDMETHOD.

  METHOD update_abapgit_ci_repo.

    update_repo( 'CI' ).

  ENDMETHOD.

  METHOD update_repo.

    DATA: lo_repo TYPE REF TO zcl_abapgit_repo_online.

    DATA(lt_repo_list) = zcl_abapgit_repo_srv=>get_instance( )->list( ).

    LOOP AT lt_repo_list ASSIGNING FIELD-SYMBOL(<repo>).

      IF <repo>->get_name( ) = iv_repo_name.
        lo_repo ?= <repo>.
      ENDIF.

    ENDLOOP.

    IF lo_repo IS NOT BOUND.
      zcx_abapgit_exception=>raise( |Couldn't find { iv_repo_name } repo| ).
    ENDIF.

    lo_repo->set_branch_name( 'refs/heads/master' ).

    DATA(ls_checks) = lo_repo->deserialize_checks( ).

    LOOP AT ls_checks-overwrite ASSIGNING FIELD-SYMBOL(<ls_overwrite>).
      <ls_overwrite>-decision = abap_true.
    ENDLOOP.

    lo_repo->deserialize( ls_checks ).

    syntax_check( lo_repo->get_package( ) ).

  ENDMETHOD.


  METHOD syntax_check.

    DATA(lt_list) = zcl_abapgit_factory=>get_syntax_check( iv_package )->run( ).

    ASSIGN lt_list[ kind = 'E' ] TO FIELD-SYMBOL(<ls_error>).
    IF sy-subrc = 0.
      zcx_abapgit_exception=>raise( |Syntax error in repo { iv_package } |
                                 && |object { <ls_error>-objtype } { <ls_error>-text } |
                                 && |{ <ls_error>-text }| ).
    ENDIF.

  ENDMETHOD.

ENDCLASS.
