MODULE output_mod
!-
!     Common Block und Definitionen der Outputvariablen fuers INCLUDE
!+
SAVE
!
CHARACTER(LEN=200)      ::  outfile      = 'fcalc.dat'
INTEGER                 ::  ityp         = 0
INTEGER                 ::  extr_abs     = 1
INTEGER                 ::  extr_ord     = 2
INTEGER                 ::  rho_extr_abs = 1
INTEGER                 ::  rho_extr_ord = 2
INTEGER                 ::  out_extr_abs = 1
INTEGER                 ::  out_extr_ord = 2
INTEGER, DIMENSION(2)   ::  out_inc ! (2)
REAL   , DIMENSION(3,3) ::  out_eck ! (3,3)
REAL   , DIMENSION(3,2) ::  out_vi  ! (3,2)
CHARACTER(LEN=  3)      ::  cpow_form    = 'tth'
!
!     COMMON /output/ outfile,ityp,extr_abs,extr_ord,                   &
!    &                rho_extr_abs,rho_extr_ord,                        &
!    &                out_extr_abs,out_extr_ord,                        &
!    &                out_eck,out_vi,out_inc,cpow_form
!
END MODULE output_mod
