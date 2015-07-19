MODULE kuplot_loop_mod
!
CONTAINS
!
      SUBROUTINE kuplot_loop
!                                                                       
      USE doact_mod 
      USE errlist_mod 
      USE learn_mod 
      USE class_macro_internal
      USE prompt_mod 
      IMPLICIT none 
!*****7*****************************************************************
!       This is the universal plot program KUPLOT. It sets up most      
!     variables and calls the loop interpreting the commands.           
!*****7*****************************************************************
!                                                                       
!                                                                       
      CHARACTER(1024) line, zeile 
      CHARACTER(4) befehl 
      LOGICAL lend 
      INTEGER lbef, lp, ll 
!
      EXTERNAL  :: kuplot_mache_kdo
!                                                                       
      lend = .false.
!                                                                       
!                                                                       
      main: DO WHILE (.not.lend) 
      CALL get_cmd (line, ll, befehl, lbef, zeile, lp, prompt) 
      ok: IF (ier_num.eq.0.and.ll.gt.0) then 
         IF (.not.(line.eq.' '.or.line (1:1) .eq.'#')) THEN
!                                                                       
!------ --- Execute command                                             
!                                                                       
         IF (befehl (1:3) .eq.'do '.or.befehl (1:2) .eq.'if') then 
            CALL do_loop (line, lend, ll, kuplot_mache_kdo) 
         ELSE 
            CALL kuplot_mache_kdo (line, lend, ll) 
         ENDIF 
         ENDIF 
      ENDIF ok
!                                                                       
!     - Handle error message                                            
!                                                                       
      fehler: IF (ier_num.ne.0) then 
         IF( ier_num ==-9.and. ier_typ==ER_IO) THEN
            write(output_io, 8000)
            write(output_io, 9000)
            stop
         ENDIF
         CALL errlist 
         IF (ier_sta.ne.ER_S_LIVE) then 
            IF (lmakro) then 
               CALL macro_close 
               prompt_status = PROMPT_ON 
            ENDIF 
            lblock = .false. 
            CALL no_error 
         ENDIF 
      ENDIF  fehler
      ENDDO main
!                                                                       
!------ END of PROGRAM                                                  
!                                                                       
      IF(lstandalone) THEN
         CALL kuplot_do_exit
      ENDIF
!                                                                       
8000 format(' ****EXIT**** Input error on normal read        ',        &
     &       '        ****',a1/)
9000 format(' ****EXIT**** Program terminated by error status',        &
     &       '        ****',a1/)
!                                                                       
      END SUBROUTINE kuplot_loop
END MODULE kuplot_loop_mod
