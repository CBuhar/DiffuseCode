MODULE discus_setup_mod
!
CONTAINS
!
SUBROUTINE discus_setup
!
USE errlist_mod
USE prompt_mod
!
!                                                                       
pname      = 'discus'
pname_cap  = 'DISCUS'
!                                                                       
blank   = ' '
prompt  = pname
prompt_status = PROMPT_ON
prompt_status_old = PROMPT_ON

!
CALL setup
CALL no_error
!
END SUBROUTINE discus_setup

SUBROUTINE setup 
!                                                                       
!     This routine makes inital setup of DISCUS                         
!                                                                       
      USE allocate_appl_mod
!
      USE prompt_mod 
!
IMPLICIT none 
!                                                                       
      include'date.inc' 
!                                                                       
CALL ini_ran (0) 
!                                                                       
!------ Write starting screen                                           
!                                                                       
version = aktuell 
WRITE ( *, 1000) version, cdate 
!
!     Call initial default allocation
!
      CALL alloc_default
!                                                                       
!     Call initialization routine.                                      
!                                                                       
CALL initarrays 
CALL init_sysarrays 
!                                                                       
!     get envirmonment information                                      
!                                                                       
CALL appl_env 
!                                                                       
!     try to read default file                                          
!                                                                       
CALL autodef 
!                                                                       
!     Check for command line parameters                                 
!                                                                       
CALL cmdline_args 
!
 1000 FORMAT (/,10x,59('*'),/,                                      &
              10x,'*',15x,'D I S C U S   Version ',a10,10x,'*',/,   &
              10x,'*',57(' '),'*',/                                 &
     &        10x,'*         Created : ',a35,3x,'*',/,              &
              10x,'*',57('-'),'*',/,                                &
     &        10x,'* (c) R.B. Neder  ',                             &
     &        '(reinhard.neder@krist.uni-erlangen.de)  *',/,        &
     &        10x,'*     Th. Proffen ',                             &
     &        '(tproffen@ornl.gov)                     *',/,        &
     &        10x,59('*'),/,                                        &
              10x,'*',57(' '),'*',/,                                &
     &        10x,'* For information on current changes',           &
     &            ' type: help News',6x,'*',/,                      &
     &        10x,'*',57(' '),'*',/,10x,59('*'),/                   &
     &                     )                                            
END SUBROUTINE setup                          
END MODULE discus_setup_mod
