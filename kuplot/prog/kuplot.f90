      PROGRAM kuplot 
!                                                                       
      USE kuplot_setup_mod
      USE kuplot_loop_mod 
      IMPLICIT none 
!
      LOGICAL, PARAMETER :: standalone = .true.
      EXTERNAL :: kuplot_sigint
!*****7*****************************************************************
!       This is the universal plot program KUPLOT. It sets up most      
!     variables and calls the loop interpreting the commands.           
!*****7*****************************************************************
!                                                                       
!                                                                       
!                                                                       
      CALL kuplot_setup (standalone)
      CALL kuplot_set_sub
      CALL SIGNAL(2, kuplot_sigint)
      CALL kuplot_loop 
!                                                                       
!                                                                       
      END PROGRAM kuplot                            
