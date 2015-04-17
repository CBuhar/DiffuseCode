!*****7**************************************************************** 
      SUBROUTINE kuplot_do_exit 
!                                                                       
!       Things to do when KUPLOT exits                                  
!                                                                       
      USE errlist_mod 
      USE prompt_mod 
      USE kuplot_config 
      USE kuplot_mod 
!                                                                       
      IMPLICIT none 
!                                                                       
!------ close PGPLOT devices                                            
!                                                                       
      CALL PGEND 
!                                                                       
!------ call system wide exit routine                                   
!                                                                       
      CALL exit_all 
!                                                                       
      END SUBROUTINE kuplot_do_exit                        
