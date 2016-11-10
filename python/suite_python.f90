MODULE suite
!
!  Module to interface python with the discus_suite
!
!  reinhard.neder@fau.de
!
!  Version initial test not ready for release
!
USE suite_python_support
!
PRIVATE
PUBLIC initialize_suite    ! Initialize the discus_suite as if started directly
PUBLIC interactive         ! start an interactive suite session
PUBLIC execute_macro       ! Execute a macro at suite, discus, diffev, kuplot
PUBLIC execute_help        ! Execute the help
PUBLIC test_macro_param    ! Test a macro for the number of parameters required by the macro
PUBLIC send_i              ! Send an integer array to the suite
PUBLIC send_r              ! Send a real valued array to the suite
PUBLIC get_i               ! Get an integer valued array from the suite
PUBLIC get_r               ! Get a real valued array from the suite
PUBLIC py_read_structure   ! Use discus/read to read a structure or unit cell
!
CONTAINS
!
SUBROUTINE initialize_suite()
!
!   Initialization of the discus_suite, to be run only once
!
USE suite_setup_mod
USE suite_loop_mod
USE suite_init_mod
USE discus_setup_mod
USE kuplot_setup_mod
USE diffev_setup_mod
USE diffev_mpi_mod
USE run_mpi_mod
!
USE prompt_mod
USE envir_mod
!
IMPLICIT NONE
!
INTEGER, PARAMETER :: master = 0 ! Master ID for MPI
EXTERNAL :: suite_sigint
!
run_mpi_myid      = 0
lstandalone       = .false.      ! No standalone for DIFFEV, DISCUS, KUPLOT
!
IF( .NOT. lsetup_done ) THEN    ! ! If necessary do initial setup
   CALL run_mpi_init    ! Do the initial MPI configuration
   CALL setup_suite     ! Define initial parameter, array values
   CALL suite_set_sub
   CALL discus_setup(lstandalone)
   CALL kuplot_setup(lstandalone)
   CALL diffev_setup(lstandalone)
   suite_discus_init = .TRUE.
   suite_kuplot_init = .TRUE.
   suite_diffev_init = .TRUE.
   pname     = 'suite'
   pname_cap = 'SUITE'
   prompt    = pname
   hlpfile   = hlpdir(1:hlp_dir_l)//pname(1:LEN(TRIM(pname)))//'.hlp'
   hlpfile_l = LEN(TRIM(hlpfile))
   IF(.NOT.run_mpi_active) THEN
      CALL suite_set_sub_cost ()
   ENDIF
   lsetup_done = .TRUE.
ELSE
   CALL suite_set_sub
ENDIF
lstandalone = .false.
!
END SUBROUTINE initialize_suite
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
SUBROUTINE interactive(prog)
!
!  Generic interface routine to start an interactive discus_suite session
!  from the python host
!
USE suite_loop_mod
USE discus_loop_mod
USE diffev_loop_mod
USE kuplot_loop_mod
USE prompt_mod
!
IMPLICIT NONE
!
CHARACTER(LEN=*), INTENT(IN)    :: prog
!
IF( .NOT. lsetup_done) CALL initialize_suite
linteractive = .TRUE.
section: SELECT CASE (prog)
   CASE ('suite')
      CALL suite_prae
      CALL suite_loop      ! Perform the normal main loop
   CASE ('discus')
      CALL discus_prae
      CALL discus_loop     ! Perform the normal discus loop
   CASE ('diffev')
      CALL diffev_prae
      CALL diffev_loop     ! Perform the normal discus loop
   CASE ('kuplot')
      CALL kuplot_prae
      CALL kuplot_loop     ! Perform the normal discus loop
END SELECT section
lsetup_done = .TRUE.
WRITE(output_io,'(a)') 'Contol returned to GUI ...'
!
END SUBROUTINE interactive
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
SUBROUTINE execute_macro(prog, line)
!
!  Execute the macro given on line for the section defined by prog
!  The macro name and all parameters must be specified, parameters
!  must be separated from each other by a comma.
!
USE suite_loop_mod
USE discus_loop_mod
USE diffev_loop_mod
USE kuplot_loop_mod
!
USE prompt_mod
!
IMPLICIT NONE
!
CHARACTER(LEN=*), INTENT(IN)    :: prog
CHARACTER(LEN=*), INTENT(INOUT) :: line
!
INTEGER :: length
!
linteractive = .FALSE.
section: SELECT CASE (prog)
   CASE ('suite')
      CALL suite_prae
   CASE ('discus')
      CALL discus_prae
   CASE ('diffev')
      CALL diffev_prae
   CASE ('kuplot')
      CALL kuplot_prae
END SELECT section
!
length = LEN_TRIM(line)
IF(line(1:1) == '@' ) THEN
   line = line(2:length)
   length = length - 1
ENDIF
!
CALL file_kdo(line,length)
exec: SELECT CASE (prog)
   CASE ('suite')
      CALL suite_loop
   CASE ('discus')
      CALL discus_loop
   CASE ('diffev')
      CALL diffev_loop
   CASE ('kuplot')
      CALL kuplot_loop
END SELECT exec
!
linteractive = .TRUE.
WRITE(output_io,'(a)') 'Contol returned to GUI ...'
!
END SUBROUTINE execute_macro
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
SUBROUTINE execute_help(prog)
!
!  Execute the help for the section defined by prog
!
!
USE prompt_mod
!
IMPLICIT NONE
!
CHARACTER(LEN=*), INTENT(IN)    :: prog
!
INTEGER :: length
!
linteractive = .TRUE.
section: SELECT CASE (prog)
   CASE ('suite')
      CALL suite_prae
   CASE ('discus')
      CALL discus_prae
   CASE ('diffev')
      CALL diffev_prae
   CASE ('kuplot')
      CALL kuplot_prae
END SELECT section
!
length = LEN_TRIM(prog)
CALL do_hel(prog, length)
!
linteractive = .TRUE.
WRITE(output_io,'(a)') 'Contol returned to GUI ...'
!
END SUBROUTINE execute_help
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
INTEGER FUNCTION test_macro_param(line)
!
CHARACTER(LEN=*), INTENT(IN) :: line
!
INTEGER :: length
INTEGER :: numpar
!
length = LEN_TRIM(line)
CALL test_macro(line,length, numpar)
test_macro_param = numpar
!
END FUNCTION test_macro_param
!
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
!
! These are generic send and get routines that are used by 
! the programs in the interface to python. They allow
! python to send / get parts of the arrays i[] and r[]
! to / from (discus, diffev, kuplot)
!
! This section used to be an independent file in lib_f90.
! As the pythion interface has moved to an explcit 
! directorty it is no longer needed in lib_f90
!
SUBROUTINE send_i (iin, lower, upper )
!
! The outer routine sends integer valued numbers for i[:]
!
USE param_mod
USE prompt_mod
IMPLICIT NONE
!
INTEGER,                         INTENT(IN) :: lower
INTEGER,                         INTENT(IN) :: upper
INTEGER, DIMENSION(lower:upper), INTENT(IN) :: iin
!
IF( .not. lsetup_done ) THEN    ! If necessary do initial setup
   CALL initialize_suite
ENDIF
!
IF(lower>0 .and. upper<UBOUND(inpara,1) .and. lower <= upper) THEN
   inpara(lower:upper) = iin(lower:upper)
ENDIF
!
END SUBROUTINE send_i
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
SUBROUTINE send_r (rin, lower, upper )
!
! The outer routine sends real valued numbers for r[:]
!
USE param_mod
USE prompt_mod
IMPLICIT NONE
!
INTEGER,                      INTENT(IN) :: lower
INTEGER,                      INTENT(IN) :: upper
REAL, DIMENSION(lower:upper), INTENT(IN) :: rin
!
IF( .not. lsetup_done ) THEN    ! If necessary do initial setup
   CALL initialize_suite
ENDIF
!
IF(lower>0 .and. upper<UBOUND(rpara,1) .and. lower <= upper) THEN
   rpara(lower:upper) = rin(lower:upper)
ENDIF
!
END SUBROUTINE send_r
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
SUBROUTINE get_i (iout, lower, upper )
!
! The outer routine gets integer valued numbers from i[:]
!
USE param_mod
USE prompt_mod
IMPLICIT NONE
!
INTEGER,                         INTENT(IN ) :: lower
INTEGER,                         INTENT(IN ) :: upper
INTEGER, DIMENSION(lower:upper), INTENT(OUT) :: iout
!
IF( .not. lsetup_done ) THEN    ! If necessary do initial setup
   CALL initialize_suite
ENDIF
!
IF(lower>0 .and. upper<UBOUND(inpara,1) .and. lower <= upper) THEN
   iout(lower:upper) = inpara(lower:upper) 
ENDIF
!
END SUBROUTINE get_i
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
SUBROUTINE get_r (rout, lower, upper )
!
! The outer routine gets real valued numbers from r[:]
!
USE param_mod
USE prompt_mod
IMPLICIT NONE
!
INTEGER,                      INTENT(IN ) :: lower
INTEGER,                      INTENT(IN ) :: upper
REAL, DIMENSION(lower:upper), INTENT(OUT) :: rout
!
IF( .not. lsetup_done ) THEN    ! If necessary do initial setup
   CALL initialize_suite
ENDIF
!
IF(lower>0 .and. upper<UBOUND(rpara,1) .and. lower <= upper) THEN
   rout(lower:upper) = rpara(lower:upper) 
ENDIF
!
END SUBROUTINE get_r
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
SUBROUTINE py_read_structure(line)
!
!  A first interface that allows to read a structre from python via
!  suite.read_cell( python_string )
!  where python string is any of: 
!       cell      crystal_structure.cell, nx, ny, nz
!       lcell     crystal_structure.cell, nx, ny, nz
!       structure crystal_structure.cell
!       free      [optional parameters]
!
USE structur
USE prompt_mod
IMPLICIT NONE
!
CHARACTER(LEN=*), INTENT(IN) :: line
!
IF( .NOT. lsetup_done) CALL initialize_suite   ! Do we need to initialize?
!
linteractive=.FALSE.    ! Tell get_cmd to get input from input_gui
CALL discus_prae        ! Switch to discus section
input_gui = line        ! copy the input line to the automatic command line
CALL read_struc         ! Call the actual task at hand
CALL back_to_suite      ! Go back to the suite
linteractive=.TRUE.     ! Tell get_cmd to read input from standard I/O
!
END SUBROUTINE py_read_structure
!
END MODULE suite
