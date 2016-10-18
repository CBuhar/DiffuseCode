MODULE molecule_func_mod
!
USE conn_mod
USE molecule_mod
!
IMPLICIT NONE
PRIVATE
PUBLIC  :: do_molecularize
PUBLIC  :: molecularize_sub
!
!
LOGICAL, DIMENSION(:  ), ALLOCATABLE :: t_list    ! Temporary list of all atoms in the molecule
!
CONTAINS
!
SUBROUTINE do_molecularize (line, length)
!
USE crystal_mod
!
USE errlist_mod
!
IMPLICIT NONE
!
CHARACTER(LEN=*), INTENT(IN) :: line
INTEGER         , INTENT(IN) :: length
!
INTEGER            , PARAMETER       :: MAXW= 20
CHARACTER(LEN=1024), DIMENSION(MAXW) :: cpara ! 
INTEGER            , DIMENSION(MAXW) :: lpara ! 
REAL               , DIMENSION(MAXW) :: werte ! 
INTEGER                              :: ianz
INTEGER                              :: istart, ifinish
INTEGER                              :: natom
INTEGER, DIMENSION(:), ALLOCATABLE   :: iatoms
INTEGER                              :: i
!
CALL get_params (line, ianz, cpara, lpara, MAXW, length)
IF(ier_num == 0) THEN
   IF(IANZ > 0 ) THEN
      CALL ber_params (ianz, cpara, lpara, werte, maxw)
      IF(ier_num == 0) THEN
         IF(NINT(werte(1)) == -1 .AND. ianz==1) THEN
            istart  = 1
            ifinish = cr_natoms
         ELSEIF(NINT(werte(1)) > 0) THEN
            istart  = NINT(werte(1))
            ifinish = istart
         ELSE
            ier_num = -6
            ier_typ = ER_FORT
         ENDIF
         IF(ier_num == 0) THEN
            natom = ianz
            ALLOCATE(iatoms(1:natom))
            iatoms(1:natom) = NINT(werte(1:ianz))
            DO i=istart,ifinish
               iatoms(1) = i
               CALL molecularize(natom,iatoms)
            ENDDO
            DEALLOCATE(iatoms)
         ENDIF
      ENDIF
   ENDIF
ENDIF
!
END SUBROUTINE do_molecularize
!
SUBROUTINE molecularize(natom,iatoms)
!
! Groups atoms starting with the first into a new molecule with new molecule type
! Atoms no. 2 etc and their connectivity are excluded.
!
USE discus_allocate_appl_mod
USE crystal_mod
USE prop_para_mod
USE errlist_mod
IMPLICIT NONE
!
INTEGER,                                  INTENT(IN)  :: natom
INTEGER, DIMENSION(1:natom),              INTENT(IN)  :: iatoms
!
INTEGER   :: jatom
!
INTEGER   :: katom
INTEGER   :: n_new,n_atom, n_type, n_mole
INTEGER   :: i, j
!
jatom   = iatoms(1)                        ! Set central atom number
IF(.NOT. btest(cr_prop(jatom),1)) THEN      ! Atom is not yet inside a molecule
!
   ALLOCATE(t_list(1:cr_natoms))              ! Make temporary list of atoms already in the molecule
   t_list(:)     = .FALSE.
   t_list(jatom) = .TRUE.
!
!  Accumulate all neighbors of the current atom into temp_list
!
   IF(natom==1) THEN
      CALL mol_add_conn(jatom)
   ELSE
      CALL mol_add_excl(jatom, natom, iatoms)
   ENDIF
   n_new = 0
   DO i=1, UBOUND(t_list,1)
      IF(t_list(i)) THEN
         n_new = n_new + 1
      ENDIF
   ENDDO
!
   n_mole = mole_num_mole + 1   ! Reserve new molecule
   n_type = mole_num_type + 1   ! Reserve new molecule type
   n_atom = mole_off(mole_num_mole) + mole_len(mole_num_mole) 

   IF ( n_mole > MOLE_MAX_MOLE  .or.  &
        n_type > MOLE_MAX_TYPE  .or.  &
        n_atom > MOLE_MAX_ATOM      ) THEN
      n_mole = MAX(n_mole,MOLE_MAX_MOLE)
      n_type = MAX(n_type,MOLE_MAX_TYPE)
      n_atom = MAX(n_atom,MOLE_MAX_ATOM)
      CALL alloc_molecule(1, 1, n_mole, n_type, n_atom)
      IF ( ier_num /= 0) THEN
         RETURN
      ENDIF
   ENDIF
   mole_num_mole = mole_num_mole + 1
   mole_num_type = mole_num_type + 1
   mole_num_atom = mole_off(mole_num_mole) + mole_len(mole_num_mole)
   mole_len(mole_num_mole)  = n_new
   mole_off(mole_num_mole)  = mole_off(mole_num_mole-1)+mole_len(mole_num_mole-1)
   mole_type(mole_num_mole) = n_type
   mole_char(mole_num_mole) = MOLE_ATOM
   mole_file(mole_num_mole) = ' '
   mole_biso(mole_num_mole) = 0.0
   j = 0
   DO i=1,UBOUND(t_list,1)
      IF(t_list(i)) THEN
         j = j + 1
         mole_cont(mole_off(mole_num_mole)+j) = i
         cr_prop(i) = ibset(cr_prop(i),PROP_MOLECULE)
      ENDIF
   ENDDO
!
!write(*,*) ' STATUS ', t_list
   DEALLOCATE(t_list)
!
ENDIF
!
END SUBROUTINE molecularize
!
!
SUBROUTINE molecularize_sub(jatom,natom,iatoms,max_sub,n_sub, sub_list)
!
! Groups atoms starting with the first into a new molecule with new molecule type
! Atoms no. 2 etc and their connectivity are excluded.
!
USE discus_allocate_appl_mod
USE crystal_mod
USE errlist_mod
IMPLICIT NONE
!
INTEGER,                                  INTENT(IN)  :: jatom
INTEGER,                                  INTENT(IN)  :: natom
INTEGER, DIMENSION(1:natom),              INTENT(IN)  :: iatoms
INTEGER,                                  INTENT(IN)  :: max_sub
INTEGER,                                  INTENT(OUT) :: n_sub
INTEGER, DIMENSION(1:max_sub),            INTENT(OUT) :: sub_list
!
INTEGER   :: i
!
!ALLOCATE(t_list(1:max_sub))              ! Make temporary list of atoms already in the molecule
ALLOCATE(t_list(1:cr_natoms))              ! Make temporary list of atoms already in the molecule
t_list(:)     = .FALSE.
t_list(jatom) = .TRUE.
!
!  Accumulate all neighbors of the current atom into temp_list
!
IF(natom==0) THEN
   CALL mol_add_conn(jatom)
ELSE
   CALL mol_add_excl(jatom, natom, iatoms)
ENDIF
n_sub = 0
DO i=1, UBOUND(t_list,1)
   IF(t_list(i)) THEN
      n_sub = n_sub + 1
      sub_list(n_sub) = i
   ENDIF
ENDDO
!write(*,*) ' Centr ', jatom
!write(*,*) ' Excl  ', natom,' : ', iatoms(:)
!write(*,*) ' GROUP ', n_sub
!write(*,*) ' GROUP ', sub_list(:)
!
!write(*,*) ' STATUS ', t_list
DEALLOCATE(t_list)
!
END SUBROUTINE molecularize_sub
!
!
RECURSIVE SUBROUTINE mol_add_conn(katom)
!
USE crystal_mod
IMPLICIT NONE
!
INTEGER , INTENT(IN) :: katom
!
INTEGER   :: ktype
INTEGER   :: ino_max  ! Number of connectivities around central atom
INTEGER   :: ino
INTEGER                              :: c_natoms  ! Number of atoms connected
CHARACTER(LEN=256)                   :: c_name    ! Connectivity name
INTEGER, DIMENSION(:  ), ALLOCATABLE :: c_list    ! List of atoms connected to current
INTEGER, DIMENSION(:,:), ALLOCATABLE :: c_offs    ! Offsets for atoms connected to current
!
INTEGER :: latom
INTEGER :: i
!
!  Accumulate all neighbors of the current atom into temp_neig
!
ktype = cr_iscat(katom)
ino_max = get_connectivity_numbers(ktype)  ! Get number of connectivity definitions
DO ino = 1, ino_max                        ! Loop over all connectivity types
   CALL get_connectivity_list(katom, ktype, ino, c_list, c_offs, c_natoms)
   DO i=1,c_natoms                         ! Loop over all neighbors
      IF(.NOT.t_list(c_list(i))) THEN      ! Not yet in the molecule
         t_list(c_list(i)) = .TRUE.        ! Add to temporary list
         latom = c_list(i)                 ! Now search current neighbor for further ones
!        Apply periodic boundary shifts to keep molecule contiguous
         IF(c_offs(1,i)/=0 .OR. c_offs(2,i)/=0 .OR. c_offs(3,i)/=0 ) THEN
            cr_pos(:,latom) = cr_pos(:,latom) + c_offs(:,i)
            CALL conn_update(latom, FLOAT(c_offs(:,i)))
         ENDIF
         CALL mol_add_conn(latom)
      ENDIF
   ENDDO
   DEALLOCATE(c_list)                      ! Remove temporary list of atoms
   DEALLOCATE(c_offs)                      ! Remove temporary offsets
ENDDO
END SUBROUTINE mol_add_conn
!
RECURSIVE SUBROUTINE mol_add_excl(katom, n_excl, excl)
!
USE crystal_mod
IMPLICIT NONE
!
INTEGER , INTENT(IN) :: katom
INTEGER , INTENT(IN) :: n_excl
INTEGER , DIMENSION(1:n_excl), INTENT(IN) :: excl
!
INTEGER   :: ktype
INTEGER   :: ino_max  ! Number of connectivities around central atom
INTEGER   :: ino
INTEGER                              :: c_natoms  ! Number of atoms connected
CHARACTER(LEN=256)                   :: c_name    ! Connectivity name
INTEGER, DIMENSION(:  ), ALLOCATABLE :: c_list    ! List of atoms connected to current
INTEGER, DIMENSION(:,:), ALLOCATABLE :: c_offs    ! Offsets for atoms connected to current
!
INTEGER :: latom
INTEGER :: i, j
!
!  Accumulate all neighbors of the current atom into temp_neig
!
ktype = cr_iscat(katom)
ino_max = get_connectivity_numbers(ktype)  ! Get number of connectivity definitions
!write(*,*) ' EXCL START  ', katom, ktype, ino_max
DO ino = 1, ino_max                        ! Loop over all connectivity types
   CALL get_connectivity_list(katom, ktype, ino, c_list, c_offs, c_natoms)
!write(*,*) ' EXCL CENTRAL', katom, c_list(1:c_natoms)
!write(*,*) ' EXCL T_LIST ', t_list
!write(*,*) ' EXCL excl   ', n_excl,' : ', excl(:)
   search: DO i=1,c_natoms                         ! Loop over all neighbors
      DO j=1,n_excl
         IF(c_list(i)==excl(j)) CYCLE search
      ENDDO
!write(*,*) ' EXCL NOT EX ', i, c_list(i), t_list(c_list(i))
      IF(.NOT.t_list(c_list(i))) THEN      ! Not yet in the molecule
         t_list(c_list(i)) = .TRUE.        ! Add to temporary list
         latom = c_list(i)                 ! Now search current neighbor for further ones
!        Apply periodic boundary shifts to keep molecule contiguous
         IF(c_offs(1,i)/=0 .OR. c_offs(2,i)/=0 .OR. c_offs(3,i)/=0 ) THEN
            cr_pos(:,latom) = cr_pos(:,latom) + c_offs(:,i)
            CALL conn_update(latom, FLOAT(c_offs(:,i)))
         ENDIF
!write(*,*) '      search ', latom
!write(*,*) ' INTE T_LIST ', t_list
         CALL mol_add_excl(latom, n_excl, excl)
      ENDIF
   ENDDO search
!write(*,*) ' ENDE T_LIST ', t_list
   DEALLOCATE(c_list)                      ! Remove temporary list of atoms
   DEALLOCATE(c_offs)                      ! Remove temporary offsets
ENDDO
END SUBROUTINE mol_add_excl
!
END MODULE molecule_func_mod
