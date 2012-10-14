MODULE powder_scat_mod
!+
!
!     variables needed for the atom lists 
!-
USE config_mod
!
SAVE
!
INTEGER                               :: POW_NMAX  = 1
INTEGER                               :: POW_MAXSCAT = 1
!
INTEGER, DIMENSION(:  ), ALLOCATABLE  :: pow_nscat ! (MAXSCAT)
INTEGER, DIMENSION(:,:), ALLOCATABLE  :: pow_iatom ! (MAXSCAT,NMAX)
!
INTEGER                               :: pown_size_of
!
!     COMMON      /powder_scat/      pow_nscat,pow_iatom
!
END MODULE powder_scat_mod
