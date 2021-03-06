MODULE diffev_refine
!
CONTAINS
   SUBROUTINE refine_no_mpi(flag_block)
!
!  Generic interface if MPI is not active 
!
   USE population
   USE run_mpi_mod
!
   USE errlist_mod
   USE mpi_slave_mod
   USE param_mod
   USE prompt_mod
   USE set_sub_generic_mod
   USE doexec_mod
   USE variable_mod
!
   IMPLICIT NONE
!
   LOGICAL , INTENT(IN)  :: flag_block    ! run_mpi was called in a do block
!
   CHARACTER (LEN=2048)  :: send_direc    ! working directory
   CHARACTER (LEN=1024)  :: zeile         ! dummy line
   INTEGER               :: send_direc_l  ! working directory length
   INTEGER               :: lzeile        ! working directory length

   INTEGER  :: i, j, k
!
   INTEGER                 :: ierr
!
   ierr = 0
!
!  Do a serial loop over all CHILDREN*NINDIV
!  Transfer the trial parameters to r[201...]
!
   zeile = run_mpi_senddata%prog(1:run_mpi_senddata%prog_l)  ! Code branch program
   lzeile = run_mpi_senddata%prog_l
!
   CALL do_cwd ( send_direc, send_direc_l )        ! Get current working directory
   run_mpi_senddata%direc_l = send_direc_l         ! Copy directory into send structure
   run_mpi_senddata%direc   = send_direc(1:MIN(send_direc_l,200))
   IF(.NOT.lstandalone) THEN
      IF(run_mpi_senddata%out(1:run_mpi_senddata%out_l) /= '/dev/null') THEN
         run_mpi_senddata%out_l   =   2                  ! Copy directory into send structure
         run_mpi_senddata%out     = 'on'
      ENDIF
   ENDIF

   inpara(201) = run_mpi_senddata%generation
   inpara(202) = run_mpi_senddata%member
   inpara(203) = run_mpi_senddata%children
   inpara(204) = run_mpi_senddata%parameters
   inpara(207) = run_mpi_senddata%nindiv    ! Needed if inside a do block
!
! Long term solution copy into specialized variables
!
   var_val( var_ref+0) = run_mpi_senddata%generation
   var_val( var_ref+1) = run_mpi_senddata%member
   var_val( var_ref+2) = run_mpi_senddata%children
   var_val( var_ref+3) = run_mpi_senddata%parameters
   var_val( var_ref+6) = run_mpi_senddata%nindiv  ! set variable: ref_nindiv
!
   kids_loop: DO i=1,run_mpi_senddata%children
      run_mpi_senddata%kid = i
      DO j=1,run_mpi_senddata%parameters                          ! Encode current trial values
         run_mpi_senddata%trial_values(j) = pop_t(j,run_mpi_senddata%kid) ! Takes value for kid
         rpara                  (200+  j) = pop_t(j,run_mpi_senddata%kid) ! Takes value for kid
         ref_para               (      j) = pop_t(j,run_mpi_senddata%kid) ! Takes value for kid
      ENDDO
      indivs_loop: DO j=1,run_mpi_senddata%nindiv
         run_mpi_senddata%indiv = j
         inpara(205) = run_mpi_senddata%kid       ! set i[205] = kid, i[206] = indiv, i[707] = nindiv
         inpara(206) = run_mpi_senddata%indiv     ! Needed if inside a do block
         var_val( var_ref+4) = run_mpi_senddata%kid     ! set variable: ref_kid 
         var_val( var_ref+5) = run_mpi_senddata%indiv   ! set variable: ref_indiv
!
         mpi_is_slave = .true.
         IF(flag_block .AND. .NOT. lstandalone) THEN
            level = level_mpi
            ilevel(level) = nlevel_mpi
            rvalue_yes = .FALSE.
            CALL p_branch(zeile, lzeile)
            IF(rvalue_yes) THEN
               trial_val(run_mpi_senddata%kid) = rvalues(2)
            ENDIF
         ELSE
            CALL p_execute_cost( run_mpi_senddata%repeat,                          &
                 LEN(run_mpi_senddata%prog),                       &
                 run_mpi_senddata%prog , run_mpi_senddata%prog_l , &
                 LEN(run_mpi_senddata%mac),                        &
                 run_mpi_senddata%mac  , run_mpi_senddata%mac_l  , &
                 LEN(run_mpi_senddata%direc),                      &
                 run_mpi_senddata%direc, run_mpi_senddata%direc_l, &
                 run_mpi_senddata%kid  , run_mpi_senddata%indiv  , &
                 run_mpi_senddata%rvalue, run_mpi_senddata%l_rvalue,     &
                 LEN(run_mpi_senddata%out),                        &
                 run_mpi_senddata%out  , run_mpi_senddata%out_l,     &
                 run_mpi_senddata%generation, run_mpi_senddata%member,   &
                 run_mpi_senddata%children, run_mpi_senddata%parameters, &
                                         run_mpi_senddata%nindiv  , &
                 run_mpi_senddata%trial_values, RUN_MPI_COUNT_TRIAL,     &
                 ierr )
         ENDIF
         mpi_is_slave = .false.
         IF(ierr/=0) THEN
            ier_msg(1) = 'A slave section exited with error message'
            WRITE(ier_msg(2), 2000)  i,j, ierr
            ier_num = -26
            ier_typ = ER_APPL
            EXIT kids_loop
         ENDIF
         IF(run_mpi_senddata%l_rvalue) THEN      ! R-value is returned
             trial_val(run_mpi_senddata%kid) = run_mpi_senddata%rvalue
         ENDIF
      ENDDO indivs_loop
   ENDDO kids_loop
!
!
2000 FORMAT('Error kid ',I4,' indiv ',I4,' is ',i8)
!
   END SUBROUTINE refine_no_mpi
END MODULE diffev_refine
