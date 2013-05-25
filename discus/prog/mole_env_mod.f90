MODULE mole_env_mod
!+
!
!     include file for molecular environment variables
!-
USE config_mod
!
SAVE
!
INTEGER, PARAMETER ::  MAX_MOLE_ENV  =  MAX_ATOM_ENV
!
INTEGER, DIMENSION(0:MAX_MOLE_ENV) ::  mole_env ! (0:MAX_MOLE_ENV)
REAL   , DIMENSION(3,MAX_MOLE_ENV) ::  mole_pos ! (3,MAX_MOLE_ENV)
!
!     COMMON  /mo_env/ mole_env,mole_pos
!
END MODULE mole_env_mod
