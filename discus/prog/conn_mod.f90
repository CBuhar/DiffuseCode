MODULE conn_mod
!
USE conn_def_mod
USE crystal_mod
!
USE errlist_mod
USE random_mod
!
IMPLICIT none
!
PRIVATE
PUBLIC  conn_menu              !  Main menu to interact with user
PUBLIC  get_connectivity_list  !  Read out the actual list of atoms around a central atom
PUBLIC  get_connectivity_identity ! Identify a connectivity definition
PUBLIC  get_connectivity_numbers  ! Read out number of connectivities for atom type
PUBLIC  do_show_connectivity   !  Show the current definitions
PRIVATE allocate_conn_list     !  Allocate memory for the connectivity
PRIVATE deallocate_conn        !  Free memory
PUBLIC  create_connectivity    !  Create the actual list of neighbors around each atom
PUBLIC  conn_do_set            !  Set parameters for the connectivity definitions
PUBLIC  conn_show              !  Main show routine
PRIVATE conn_test              !  While developing, a routine to test functionality
PRIVATE do_bond_switch         !  Perform a bond witching operation
PRIVATE get_connect_pointed    !  Read out connectivity list return the pointer to list
PRIVATE do_exchange            !  Helper to exchange atoms between connectivities
PUBLIC  conn_update            !  Update the connectivity for an atom
!
INTEGER, PARAMETER              :: MAX_ATOM=10
!
! TYPE NEIGHBORS  is a linear chain to be filled with the actual neighboring atoms
!                 currently only the neighbor number is stored no further info, as
!                 I do not want to update this list all the time.
TYPE :: NEIGHBORS
   INTEGER                      :: atom_number
   INTEGER, DIMENSION(1:3)      :: offset
   TYPE (NEIGHBORS), POINTER    :: next
END TYPE
!
! TYPE NEIGHBORHOOD is a linear chain of the possible neighborhoods.
!                   Each node branches off to one side with the actual neighboring atoms
TYPE :: NEIGHBORHOOD
   INTEGER                      :: central_number     ! absolute number of central atom
   INTEGER                      :: central_type       ! central atom is of this type
   INTEGER                      :: neigh_type         ! this neighbors belongs to this definition
   CHARACTER (LEN=256)          :: conn_name          ! Connectivity name
   INTEGER                      :: conn_name_l        ! Connectivity name length
   REAL                         :: distance_min       ! minimum distance to neighbors
   REAL                         :: distance_max       ! maximum distance to neighbors
   INTEGER                      :: natoms             ! number of neighbors
   TYPE (NEIGHBORS), POINTER    :: nachbar            ! The actual list of neighboring atoms
   TYPE (NEIGHBORHOOD), POINTER :: next_neighborhood  ! A next neighborhood
END TYPE
!
! TYPE MAIN_LIST is a structure that contains info on the central atom, as
!                well as a pointer to the NEIGHBORHOOD
TYPE :: MAIN_LIST
   INTEGER                      :: number
   TYPE (NEIGHBORHOOD), POINTER :: liste
END TYPE
!
! In order to have FAST access to the neighborhood of any atom, an
! allocatable array is defined. Entry at_conn(i) gives access to the 
! neighborhood of atom i
TYPE (main_list), DIMENSION(:), ALLOCATABLE :: at_conn
!
! (temporary) pointers of TYPE NEIGHBORS. This allows to move along the 
! neighbors in an individual neighborhood.
TYPE (NEIGHBORS), POINTER       :: head, tail, temp, sw_central, sw_second
!
! (temporary) pointers of TYPE NEIGHBORHOOD. This allows to move along the 
! neighborhoods of an individual atom.
TYPE (NEIGHBORHOOD), POINTER       :: hood_head
TYPE (NEIGHBORHOOD), POINTER       :: hood_temp
TYPE (NEIGHBORHOOD), POINTER       :: hood_central
TYPE (NEIGHBORHOOD), POINTER       :: hood_second
!
LOGICAL                            :: conn_status = .false.
!
CONTAINS
!
!  Module procedures to allocate, deallocate,
!
   SUBROUTINE allocate_conn_list(MAX_ATOM)
!
!  Simply allocates the connectivity list
!
   IMPLICIT  none
!
   INTEGER, INTENT(in)  :: MAX_ATOM
!
   INTEGER              :: i
!
   IF(.not. ALLOCATED(at_conn)) THEN
      ALLOCATE (at_conn(1:MAX_ATOM))                 ! allocate the array
      DO i=1,MAX_ATOM                                ! initialise the array
        at_conn(i)%number       = 0
        NULLIFY (at_conn(i)%liste)                   ! Initialy no NEIGHBORHOOD
      END DO
   ENDIF
   END SUBROUTINE allocate_conn_list
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!
   SUBROUTINE deallocate_conn(MAX_ATOM)
!
!  Properly deallocates the connectivity list
!
   IMPLICIT  none
!
   INTEGER, INTENT(in)  :: MAX_ATOM
!
   INTEGER              :: i
!
!
! Do proper removal of connectivity list
!
   IF(ALLOCATED(at_conn)) THEN
      cln_nghb : DO i=1,MAX_ATOM                         ! Loop over all atoms
        liste: IF ( ASSOCIATED(at_conn(i)%liste) ) THEN  ! If neighborhood was created
          hood_temp => at_conn(i)%liste                  ! point to the first neighborhood
          hood_head => at_conn(i)%liste
          hood: DO WHILE ( ASSOCIATED(hood_temp) )       ! While there are further neighborhood
             temp => hood_temp%nachbar                   ! point to the first neighbor within current neigborhood
             head => hood_temp%nachbar
             DO WHILE ( ASSOCIATED(temp) )               ! While there are further neighbors
               temp => temp%next                         ! Point to next neighbor
!              IF(ALLOCATED(head)) THEN
               IF(ASSOCIATED(head)) THEN
                  DEALLOCATE ( head )                       ! deallocate previous neighbor
               ENDIF
               head => temp                              ! also point to next neighbor
             END DO
             hood_temp => hood_temp%next_neighborhood    ! Point to next neighborhood
!            IF(ALLOCATED(hood_head)) THEN
             IF(ASSOCIATED(hood_head)) THEN
                DEALLOCATE ( hood_head )                 ! deallocate previous neighborhood
             ENDIF
             hood_head => hood_temp
          END DO hood                                    ! Loop over neighborhoods
        END IF liste                                     ! If atom has neigborhoods
      END DO cln_nghb                                    ! Loop over atoms
!
!
      DEALLOCATE (at_conn )                     ! Deallocate the initial array
!
      conn_status = .false.
   ENDIF
!
   END SUBROUTINE deallocate_conn
!
   SUBROUTINE create_connectivity
!
!  Performs a loop over all atoms and creates the individual connectivities
!
   USE chem_mod
   USE crystal_mod
   USE atom_env_mod
   USE modify_mod
!
   IMPLICIT NONE
!
!  INTEGER, INTENT(IN)  :: i
!
   INTEGER, PARAMETER  :: MIN_PARA = 1
   INTEGER             :: maxw
!
   REAL   , DIMENSION(MAX(MIN_PARA,MAXSCAT+1)) :: werte ! Array for neighbors
!
   INTEGER              :: j,i
   INTEGER              :: is  ! dummies for scattering types
   INTEGER              :: ianz
   INTEGER              :: n_neig      ! Actual number of neighboring atoms
   LOGICAL, DIMENSION(3):: fp    ! periodic boundary conditions
   LOGICAL              :: fq    ! quick search algorithm
   REAL                 :: rmin        ! Minimum bond length
   REAL                 :: rmax        ! Maximum bond length
   REAL   , DIMENSION(3)     :: x      ! Atom position
!
   maxw = MAX(MIN_PARA, MAXSCAT+1)
!
   CALL deallocate_conn(conn_nmax)                     ! Deallocate old connectivity
   conn_nmax = cr_natoms                               ! Remember current atom number
   CALL allocate_conn_list(conn_nmax)                  ! Allocate connectivity
!
   fp (1) = chem_period (1)
   fp (2) = chem_period (2)
   fp (3) = chem_period (3)
   fq     = chem_quick
!
   atome: DO i = 1,cr_natoms                                ! Check all atoms in the structure    
      x(1) = cr_pos(1,i)
      x(2) = cr_pos(2,i)
      x(3) = cr_pos(3,i)
      ianz = 1
      is   = cr_iscat(i)                                    ! Keep atom type
      allowed: IF ( ASSOCIATED(def_main(is)%def_liste )) THEN  ! def.s exist
         def_temp => def_main(is)%def_liste
         neighs: DO
            werte(1:def_temp%valid_no) =      &
               def_temp%valid_types(1:def_temp%valid_no)    ! Copy valid atom types
            ianz  = def_temp%valid_no                       ! Copy no. of valid atom types
            rmin     = def_temp%def_rmin                    ! Copy distance limits
            rmax     = def_temp%def_rmax
            CALL do_find_env (ianz, werte, maxw, x, rmin,rmax, fq, fp)
            at_conn(i)%number = i                           ! Just set atom no
!
            IF ( atom_env(0) > 0) THEN                      ! The atom has neighbors
!
!              Properly set the pointer hood_temp
!
               IF ( ASSOCIATED(at_conn(i)%liste)) THEN      ! A previous NEIGHBORHOOD exists
                  ALLOCATE(hood_temp%next_neighborhood)     ! Create one NEIGHBORHOOD
                  hood_temp => hood_temp%next_neighborhood  ! Point to the new NEIGHBORHOOD
               ELSE
                  ALLOCATE (at_conn(i)%liste)               ! Create one NEIGHBORHOOD
                  hood_temp => at_conn(i)%liste             ! Point to current NEIGHBORHOOD
               ENDIF
!
!           Now we set parameters of current NEIGHBORHOOD
!
               IF(def_temp%intend_no == -1) THEN
                  n_neig = atom_env(0)
               ELSE
                  n_neig = MIN(atom_env(0),def_temp%intend_no)
               ENDIF
               NULLIFY (hood_temp%next_neighborhood)        ! No further NEIGHBORHOODs
               hood_temp%central_number = i                 ! Just set central atom no.
               hood_temp%central_type   = cr_iscat(i)
               hood_temp%neigh_type     = def_temp%valid_id   ! Set definition type number
               hood_temp%conn_name      = def_temp%def_name   ! Set name from definition type
               hood_temp%conn_name_l    = def_temp%def_name_l ! Set name length from definition type
               hood_temp%natoms         = n_neig              ! Set number of neighbors
               NULLIFY (hood_temp%nachbar)                  ! Initially there are no NEIGHBORS
!
               ALLOCATE (hood_temp%nachbar)                 ! create the first NEIGHBOR slot
               j = 1
               tail => hood_temp%nachbar                    ! tail points to the first NEIGHBOR
               tail%atom_number = atom_env(j)               ! I store the atom_no of the neighbor
               tail%offset(1)   = NINT(atom_pos(1,j)-cr_pos(1,atom_env(j)))
               tail%offset(2)   = NINT(atom_pos(2,j)-cr_pos(2,atom_env(j)))
               tail%offset(3)   = NINT(atom_pos(3,j)-cr_pos(3,atom_env(j)))
               NULLIFY (tail%next)                          ! No further neighbors
!
               DO j = 2, n_neig                             ! Add all (intended) neighbors to list
                  ALLOCATE (tail%next)                      ! create a further NEIGHBOR
                  tail => tail%next                         ! reassign tail to new end of list
                  tail%atom_number = atom_env(j)            ! I store the atom_no of the neighbor
                  tail%offset(1)   = NINT(atom_pos(1,j)-cr_pos(1,atom_env(j)))
                  tail%offset(2)   = NINT(atom_pos(2,j)-cr_pos(2,atom_env(j)))
                  tail%offset(3)   = NINT(atom_pos(3,j)-cr_pos(3,atom_env(j)))
                  NULLIFY (tail%next)                       ! No further neighbors
               ENDDO
            ENDIF
            IF ( .NOT. ASSOCIATED(def_temp%def_next)) THEN  ! No more def.s
               CYCLE atome
            ENDIF
            def_temp => def_temp%def_next
         ENDDO neighs                                       ! Loop over def.s
      ENDIF allowed                                         ! Atom has def.s
   ENDDO atome                                              ! Loop over all atoms in structure
!
   conn_status = .true.
!
   END SUBROUTINE create_connectivity
!
   SUBROUTINE recreate_connectivity(itype, ino, c_name)
!
!  Performs a loop over all atoms and creates the individual connectivities
!
   USE chem_mod
   USE crystal_mod
   USE atom_env_mod
   USE modify_mod
!
   IMPLICIT NONE
!
   INTEGER           , INTENT(IN)     :: itype   ! Atom type
   INTEGER           , INTENT(INOUT)  :: ino     ! Connectivity def. no.
   CHARACTER(LEN=256), INTENT(INOUT)  :: c_name  ! Connectivity name
!
!  INTEGER, INTENT(IN)  :: i
!
   INTEGER, PARAMETER  :: MIN_PARA = 1
   INTEGER             :: maxw
!
   REAL   , DIMENSION(MAX(MIN_PARA,MAXSCAT+1)) :: werte ! Array for neighbors
!
   INTEGER              :: j,i
   INTEGER              :: is  ! dummies for scattering types
   INTEGER              :: ianz
   INTEGER              :: n_neig      ! Actual number of neighboring atoms
   LOGICAL, DIMENSION(3):: fp    ! periodic boundary conditions
   LOGICAL              :: fq    ! quick search algorithm
   LOGICAL              :: found_def   ! Found correct neiborhood def to replace
   LOGICAL              :: found       ! Found correct neiborhood to replace
   REAL                 :: rmin        ! Minimum bond length
   REAL                 :: rmax        ! Maximum bond length
   REAL   , DIMENSION(3)     :: x      ! Atom position
!
   maxw = MAX(MIN_PARA, MAXSCAT+1)
!
!  CALL deallocate_conn(conn_nmax)                     ! Deallocate old connectivity
   conn_nmax = cr_natoms                               ! Remember current atom number
   IF ( .NOT.ALLOCATED(at_conn)) THEN                 ! No previous NEIGHBORHOOD exists
      CALL allocate_conn_list(conn_nmax)               ! Allocate connectivity
   ENDIF
!
   fp (1) = chem_period (1)
   fp (2) = chem_period (2)
   fp (3) = chem_period (3)
   fq     = chem_quick
!
   atome: DO i = 1,cr_natoms                                ! Check all atoms in the structure    
      is   = cr_iscat(i)                                    ! Keep atom type
      IF(is/=itype) CYCLE atome
      x(1) = cr_pos(1,i)
      x(2) = cr_pos(2,i)
      x(3) = cr_pos(3,i)
      ianz = 1
      allowed: IF ( ASSOCIATED(def_main(is)%def_liste )) THEN  ! def.s exist
         def_temp => def_main(is)%def_liste
         found_def = .FALSE.
         neighs: DO
            IF(.NOT.(ino==def_temp%valid_id .OR. c_name==def_temp%def_name)) THEN
               def_temp => def_temp%def_next                ! not the right definition,
               CYCLE neighs                                 ! go to next definition
            ENDIF
            found_def = .TRUE.
            werte(1:def_temp%valid_no) =      &
               def_temp%valid_types(1:def_temp%valid_no)    ! Copy valid atom types
            ianz  = def_temp%valid_no                       ! Copy no. of valid atom types
            rmin     = def_temp%def_rmin                    ! Copy distance limits
            rmax     = def_temp%def_rmax
            CALL do_find_env (ianz, werte, maxw, x, rmin,rmax, fq, fp)
            at_conn(i)%number = i                           ! Just set atom no
!
            IF ( atom_env(0) > 0) THEN                      ! The atom has neighbors
!
!              Properly set the pointer hood_temp
!
               found = .FALSE.
               IF ( ASSOCIATED(at_conn(i)%liste)) THEN      ! A previous NEIGHBORHOOD exists
                  hood_temp => at_conn(i)%liste             ! Point to current NEIGHBORHOOD
find_hood:        DO WHILE(ASSOCIATED(hood_temp))
                     IF(ino==hood_temp%neigh_type .OR. &
                        c_name==hood_temp%conn_name   ) THEN ! Found the correct neighborhood
                        found = .TRUE.
                        EXIT find_hood
                     ENDIF
                     hood_temp => hood_temp%next_neighborhood  ! Point to the next NEIGHBORHOOD
                  ENDDO find_hood
                  IF(found) THEN                            ! We are at correct neighborhood
                     CONTINUE                               ! Deallocate old neighbors
                     temp => hood_temp%nachbar              ! point to the first neighbor within current neigborhood
                     head => hood_temp%nachbar
                     DO WHILE ( ASSOCIATED(temp) )          ! While there are further neighbors
                       temp => temp%next                    ! Point to next neighbor
                       IF(ASSOCIATED(head)) THEN
                          DEALLOCATE ( head )               ! deallocate previous neighbor
                       ENDIF
                       head => temp                         ! also point to next neighbor
                     END DO
                  ELSE                                      ! No neighborood found thus:
                     ALLOCATE(hood_temp%next_neighborhood)     ! Create one NEIGHBORHOOD
                     hood_temp => hood_temp%next_neighborhood  ! Point to the new NEIGHBORHOOD
                  ENDIF
               ELSE
                  ALLOCATE (at_conn(i)%liste)               ! Create one NEIGHBORHOOD
                  hood_temp => at_conn(i)%liste             ! Point to current NEIGHBORHOOD
                  NULLIFY (hood_temp%next_neighborhood)     ! No further NEIGHBORHOODs
               ENDIF
!
!           Now we set parameters of current NEIGHBORHOOD
!
               IF(def_temp%intend_no == -1) THEN
                  n_neig = atom_env(0)
               ELSE
                  n_neig = MIN(atom_env(0),def_temp%intend_no)
               ENDIF
               hood_temp%central_number = i                 ! Just set central atom no.
               hood_temp%central_type   = cr_iscat(i)
               hood_temp%neigh_type     = def_temp%valid_id   ! Set definition type number
               hood_temp%conn_name      = def_temp%def_name   ! Set name from definition type
               hood_temp%conn_name_l    = def_temp%def_name_l ! Set name length from definition type
               hood_temp%natoms         = n_neig              ! Set number of neighbors
               NULLIFY (hood_temp%nachbar)                  ! Initially there are no NEIGHBORS
!
               ALLOCATE (hood_temp%nachbar)                 ! create the first NEIGHBOR slot
               j = 1
               tail => hood_temp%nachbar                    ! tail points to the first NEIGHBOR
               tail%atom_number = atom_env(j)               ! I store the atom_no of the neighbor
               tail%offset(1)   = NINT(atom_pos(1,j)-cr_pos(1,atom_env(j)))
               tail%offset(2)   = NINT(atom_pos(2,j)-cr_pos(2,atom_env(j)))
               tail%offset(3)   = NINT(atom_pos(3,j)-cr_pos(3,atom_env(j)))
               NULLIFY (tail%next)                          ! No further neighbors
!
               DO j = 2, n_neig                             ! Add all (intended) neighbors to list
                  ALLOCATE (tail%next)                      ! create a further NEIGHBOR
                  tail => tail%next                         ! reassign tail to new end of list
                  tail%atom_number = atom_env(j)            ! I store the atom_no of the neighbor
                  tail%offset(1)   = NINT(atom_pos(1,j)-cr_pos(1,atom_env(j)))
                  tail%offset(2)   = NINT(atom_pos(2,j)-cr_pos(2,atom_env(j)))
                  tail%offset(3)   = NINT(atom_pos(3,j)-cr_pos(3,atom_env(j)))
                  NULLIFY (tail%next)                       ! No further neighbors
               ENDDO
            ENDIF
            IF(found) CYCLE atome
            IF ( .NOT. ASSOCIATED(def_temp%def_next)) THEN  ! No more def.s
               CYCLE atome
            ENDIF
            def_temp => def_temp%def_next
         ENDDO neighs                                       ! Loop over def.s
            IF(.NOT.found_def) THEN                             ! found no correct definition
               ier_num = -109
               ier_typ = ER_APPL
               ier_msg(1) = 'None of the connectivity definitions for the'
               ier_msg(2) = 'atom type to be renewed matches the number or name'
               RETURN
            ENDIF
      ENDIF allowed                                         ! Atom has def.s
   ENDDO atome                                              ! Loop over all atoms in structure
!
   conn_status = .true.
!
   END SUBROUTINE recreate_connectivity
!
!
   SUBROUTINE conn_do_set ( code, zeile, length)
!-                                                                      
!     Set the parameters for the connectivity
!+                                                                      
      USE discus_allocate_appl_mod 
      USE discus_config_mod 
      USE crystal_mod 
      USE modify_mod
      USE variable_test
!
      IMPLICIT none
!
!
      INTEGER          , INTENT(IN   )  :: code 
      CHARACTER (LEN=*), INTENT(INOUT)  :: zeile
      INTEGER          , INTENT(INOUT)  :: length 
!
      INTEGER, PARAMETER  :: MIN_PARA = 5
      INTEGER             :: maxw
      INTEGER, PARAMETER  :: maxw2 = 2
!
      CHARACTER(LEN=1024), DIMENSION(MAX(MIN_PARA,MAXSCAT+5)) :: cpara
      INTEGER            , DIMENSION(MAX(MIN_PARA,MAXSCAT+5)) :: lpara
      REAL               , DIMENSION(MAX(MIN_PARA,MAXSCAT+5)) :: werte
!
      CHARACTER(LEN=1024), DIMENSION(2)  :: ccpara
      INTEGER            , DIMENSION(2)  :: llpara
      REAL               , DIMENSION(2)  :: wwerte
!
      INTEGER             :: ianz         ! number of command line parameters
      INTEGER             :: iianz        ! dummy number
      INTEGER             :: is1          ! first atom type
      INTEGER             :: is2          ! second atom type
      INTEGER             :: temp_id      ! temporary definition ID
      INTEGER             :: temp_number  ! temporary Number of neighbors
      INTEGER             :: work_id      ! ID of the definition to change/delete
      CHARACTER(LEN=256)  :: work_name    ! Name of the definition to change/delete
      INTEGER             :: work_name_l  ! Length of name for the definition to change/delete
      LOGICAL             :: lnew         ! require atom type to exist
      LOGICAL             :: l_exist      ! TRUE if conn. name is a variable name
      LOGICAL             :: l_type       ! Unused DUMMY argument
      INTEGER             :: is_no        ! Unused DUMMY argument
      INTEGER             :: all_status   ! Allocation status
      REAL                :: rmin         ! minimum bond distance
      REAL                :: rmax         ! maximum bond distance
!
      REAL :: berechne
!                                                                       
      rmin = 0.0
      rmax = 0.5
      maxw = MAX(MIN_PARA, MAXSCAT+5)     ! (MAXSCAT+ void) + 4 Parameters  
!                                                                       
!     Check definitions array
!
      IF ( .NOT. ALLOCATED(def_main)) THEN
         ALLOCATE (def_main(0:MAXSCAT), stat = all_status) 
         DO is1 = 0, MAXSCAT
            NULLIFY(def_main(is1)%def_liste)
            def_main(is1)%def_id     = is1
            def_main(is1)%def_number = 0
         ENDDO
!        conn_max_def = MAXSCAT
         IF ( all_status /= 0 ) THEN
            ier_num = -3
            ier_typ = ER_COMM
            ier_msg(1) = ' Error allocating the definitions'
            WRITE(ier_msg(2),'(a,i6)') 'Error no:',all_status
            RETURN
         ENDIF
      ENDIF
!
!     Get parameters from input line
!
      CALL get_params (zeile, ianz, cpara, lpara, maxw, length) 
      IF (ier_num.ne.0) return 
!
!     Remove all definitions 
!
      reset: IF ( code == code_res ) THEN        ! remove all definitions
         exist_def: IF ( ALLOCATED(def_main)) THEN    ! Are there any definitions
            DO is1 = 0, MAXSCAT
               is_range: IF (is1 <= UBOUND(def_main,1) ) THEN 
               is_reset: IF ( ASSOCIATED(def_main(is1)%def_liste) ) THEN  ! A list of definitions exists
                  def_head => def_main(is1)%def_liste
                  def_temp => def_main(is1)%def_liste
                  work_id = 1
                  DO WHILE ( ASSOCIATED(def_temp%def_next) )        ! A further definition exists
                     IF ( work_id == 1 ) THEN                       ! This is the first def.
                        def_main(is1)%def_liste => def_temp%def_next  ! properly point in def_main
                        DEALLOCATE(def_temp, stat=all_status)       ! Remove this node
                        def_temp => def_main(is1)%def_liste         ! Point to next node
                     ELSE                                           ! Not the first definition
                        def_head%def_next   => def_temp%def_next    ! Point previous next to further
                        DEALLOCATE(def_temp, stat=all_status)       ! Remove this node
                        def_temp => def_head%def_next               ! Point to next node
                        work_id = work_id + 1                       ! Increment node number
                     ENDIF
                  ENDDO
                  DEALLOCATE(def_main(is1)%def_liste, stat=all_status) !Remove the whole list for this scat type
               ENDIF is_reset
               ENDIF is_range
            ENDDO
            DEALLOCATE(def_main, stat=all_status)                   ! Deallocate the main structure
         ENDIF exist_def
         RETURN                           ! All definitions have been removed
      ENDIF reset
!
!     All other codes
!
      IF ((code==code_del .AND. ianz/=2) .OR. (code/=code_del .AND.ianz < 4)) THEN
         ier_num = -6         ! Wrong number of input parameters
         ier_typ = ER_COMM
         return      ! At least four parameters
      ENDIF
!                                                                       
      iianz = 1
      lnew  = .false.
!
!     Get the first atom type
!
      CALL get_iscat (iianz, cpara, lpara, werte, maxw, lnew)
      is1 = NINT(werte(1))
      CALL del_params (1, ianz, cpara, lpara, maxw) 
!
      IF ( code /= code_add ) then
         iianz = 1
         CALL ber_params (iianz, cpara, lpara, werte, maxw)
         IF(ier_num == 0) THEN
            work_id     = NINT(werte(1))
            work_name   = ' '
            work_name_l = 1
         ELSE
            work_id     = -2
            work_name   = cpara(iianz)(1:lpara(iianz))
            work_name_l = lpara(iianz)
            call no_error
         ENDIF
         CALL variable_exist (work_name, work_name_l,0, l_exist, l_type, is_no)
         IF(l_exist) THEN
            ier_num = -120
            ier_typ = ER_APPL
            RETURN
         ENDIF
         CALL discus_validate_var_spec(work_name, work_name_l)
         IF( ier_num == -25 ) THEN
            ier_num = -120
            ier_typ = ER_APPL
            RETURN
         ENDIF
         CALL del_params (1, ianz, cpara, lpara, maxw) 
      ELSE
         work_id     = -1
         work_name   = cpara(ianz)(1:lpara(ianz))
         work_name_l = lpara(ianz)
         ianz        = ianz - 1
         IF(cpara(ianz)(1:6)=='first_') THEN
            cpara(ianz) = cpara(ianz)(7:lpara(ianz))
            temp_number = NINT(berechne(cpara(ianz), lpara(ianz)))
            ianz        = ianz - 1
         ELSE
            temp_number = -1
         ENDIF
      ENDIF
!
      IF ( code /= code_del ) THEN
!
!     Get minimum and maximum bond length, last two parameters
!
         ccpara(1) = cpara(ianz-1)
         llpara(1) = lpara(ianz-1)
         ccpara(2) = cpara(ianz  )
         llpara(2) = lpara(ianz  )
         iianz     = 2
         CALL ber_params (iianz, ccpara, llpara, wwerte, maxw2)
         rmin = wwerte(1)
         rmax = wwerte(2)
         ianz = ianz - 2
!
!     get scattering types of neighbors
!
         CALL get_iscat (ianz, cpara, lpara, werte, maxw, lnew)
      ENDIF
!
      is_there: IF ( ASSOCIATED(def_main(is1)%def_liste) ) THEN  ! A list of definitions exists
         is_work: IF ( work_id /= -1 ) THEN                      ! Work on an existing definition
            IF ( work_id > def_main(is1)%def_number ) THEN       ! Definition does not exist
               ier_num = -109
               ier_typ = ER_APPL
               RETURN
            ENDIF
            def_head => def_main(is1)%def_liste
            def_temp => def_main(is1)%def_liste
            search: DO                                           ! search for working definition
               IF ( .NOT. ASSOCIATED(def_temp)) THEN             ! target is not associated ERROR
                  ier_num = -109
                  ier_typ = ER_APPL
                  RETURN
               ENDIF
               IF ( work_id   == def_temp%valid_id  .OR. &
                    work_name == def_temp%def_name       ) THEN  ! Found working definition
                  work_id   = def_temp%valid_id                  ! Make sure ID matches
                  work_name = def_temp%def_name                  ! Make sure name matches
                  EXIT search
               ENDIF
               def_head => def_temp
               def_temp => def_temp%def_next
            ENDDO search                                         ! End search for working definition
            IF ( code == code_set ) THEN                         ! Replace current entries
               DEALLOCATE( def_temp%valid_types, stat = all_status) ! delete old arry
               IF ( all_status /= 0 ) THEN
                  ier_num = -3
                  ier_typ = ER_COMM
                  ier_msg(1) = ' Error allocating the definitions'
                  WRITE(ier_msg(2),'(a,i6)') 'Error no:',all_status
                  RETURN
               ENDIF
               ALLOCATE ( def_temp%valid_types(1:ianz), stat = all_status) ! alloc array of neighbor types
               IF ( all_status /= 0 ) THEN
                  ier_num = -3
                  ier_typ = ER_COMM
                  ier_msg(1) = ' Error allocating the definitions'
                  WRITE(ier_msg(2),'(a,i6)') 'Error no:',all_status
                  RETURN
               ENDIF
               DO is2 = 1, ianz                                  ! Set all neighbor types
                  def_temp%valid_types(is2) = NINT(werte(is2))
               ENDDO
               def_temp%valid_no  = ianz                         ! Set number of neighb or types
               def_temp%intend_no = temp_number                  ! Set intended number of neighbor atoms
               def_temp%def_rmin  = rmin                         ! Set bond length limits
               def_temp%def_rmax  = rmax                         ! Set bond length limits
            ELSEIF ( code == code_del ) THEN                     ! Remove this definition
               IF ( ASSOCIATED(def_temp%def_next) ) THEN         ! A further definition exists
                  IF ( work_id == 1 ) THEN                       ! This is the first def.
                     def_main(is1)%def_liste => def_temp%def_next  ! properly point in def_main
                     DEALLOCATE(def_temp)                        ! Remove this node
                     def_temp => def_main(is1)%def_liste         ! Point to next node
                  ELSE                                           ! Not the first definition
                     def_head%def_next   => def_temp%def_next    ! Point previous next to further
                     DEALLOCATE(def_temp)                        ! Remove this node
                     def_temp => def_head%def_next               ! Point to next node
                  ENDIF
                  def_temp%valid_id = def_temp%valid_id -1       ! Decrement the ID of current node
                  def_temp => def_temp%def_next                  ! Point to next node
                  search3: DO                                    ! Decrement ID's of all further nodes
                     IF ( ASSOCIATED(def_temp)) THEN
                        def_temp%valid_id = def_temp%valid_id -1
                     ELSE
                        EXIT search3
                     ENDIF
                     def_temp => def_temp%def_next
                  ENDDO search3
               ELSE                                              ! No further definition exists
                  IF ( work_id == 1 ) THEN                       ! This is the first def.
                     DEALLOCATE(def_main(is1)%def_liste)         ! Remove the whole list for this scat type
                  ELSE                                           ! Not the first definition
                     NULLIFY(def_head%def_next)                  ! Nullify previous pointer to next
                     DEALLOCATE(def_temp)                        ! Remove current definition
                  ENDIF
               ENDIF
            ENDIF
         ELSE is_work                                            ! Add a new definition
            def_head => def_main(is1)%def_liste                  ! Point to first def.
            def_temp => def_main(is1)%def_liste                  ! Point to first def.
            temp_id  = 0                                         ! In case we have no def.s at all
            search2: DO                                          ! search for working definition
               IF ( .NOT. ASSOCIATED(def_temp)) THEN             ! TRUE if at end of definitions
                  EXIT search2
               ENDIF
               def_head => def_temp                              ! Increment point to next def.
               def_temp => def_temp%def_next                     ! Increment point to next def.
               temp_id  = def_head%valid_id                      ! Store previous ID number
            ENDDO search2                                        ! End search for working definition
            ALLOCATE(def_temp, stat=all_status)                  ! Allocate a next node
            IF ( all_status /= 0 ) THEN
               ier_num = -3
               ier_typ = ER_COMM
               ier_msg(1) = ' Error allocating the definitions'
               WRITE(ier_msg(2),'(a,i6)') 'Error no:',all_status
               RETURN
            ENDIF
            ALLOCATE ( def_temp%valid_types(1:ianz), stat = all_status) ! alloc array of neighbor types
            IF ( all_status /= 0 ) THEN
               ier_num = -3
               ier_typ = ER_COMM
               ier_msg(1) = ' Error allocating the definitions'
               WRITE(ier_msg(2),'(a,i6)') 'Error no:',all_status
               RETURN
            ENDIF
            def_head%def_next => def_temp                     ! Point previous def. to current
            DO is2 = 1, ianz                                  ! Set all neighbor types
               def_temp%valid_types(is2) = NINT(werte(is2))
            ENDDO
            def_temp%valid_id   = temp_id + 1                 ! Set number of neighb or types
            def_temp%def_name   = work_name                   ! Set definition name
            def_temp%def_name_l = work_name_l                 ! Set definition name length
            def_temp%valid_no   = ianz                        ! Set number of neighb or types
            def_temp%intend_no  = temp_number                 ! Set intended number of neighbor atoms
            def_temp%def_rmin   = rmin                        ! Set bond length limits
            def_temp%def_rmax   = rmax                        ! Set bond length limits
            NULLIFY(def_temp%def_next)                        ! No further definition
            def_main(is1)%def_number = def_main(is1)%def_number + 1
         ENDIF is_work
      ELSE  is_there                                          ! No list exists yet, add first node
         IF ( code == code_add ) THEN                         ! Replace current entries
            ALLOCATE(def_main(is1)%def_liste, stat = all_status) ! allocate a list of defs.
            def_main(is1)%def_id     = is1                    ! Set identifier
            def_main(is1)%def_number = 0                      ! No def.s exist yet.
            IF ( all_status /= 0 ) THEN
               ier_num = -3
               ier_typ = ER_COMM
               ier_msg(1) = ' Error allocating the definitions'
               WRITE(ier_msg(2),'(a,i6)') 'Error no:',all_status
               RETURN
            ENDIF
            def_temp => def_main(is1)%def_liste
            ALLOCATE ( def_temp%valid_types(1:ianz), stat = all_status) ! alloc array of neighbor types
            IF ( all_status /= 0 ) THEN
               ier_num = -3
               ier_typ = ER_COMM
               ier_msg(1) = ' Error allocating the definitions'
               WRITE(ier_msg(2),'(a,i6)') 'Error no:',all_status
               RETURN
            ENDIF
            DO is2 = 1, ianz                                  ! Set all neighbor types
               def_temp%valid_types(is2) = NINT(werte(is2))
            ENDDO
            def_temp%valid_id   = 1                           ! Set number of neighb or types
            def_temp%def_name   = work_name                   ! Set definition name
            def_temp%def_name_l = work_name_l                 ! Set definition name length
            def_temp%valid_no   = ianz                        ! Set number of neighb or types
            def_temp%intend_no  = temp_number                 ! Set intended number of neighbor atoms
            def_temp%def_rmin   = rmin                        ! Set bond length limits
            def_temp%def_rmax   = rmax                        ! Set bond length limits
            NULLIFY(def_temp%def_next)                        ! No further definition
            def_main(is1)%def_number = def_main(is1)%def_number + 1
         ENDIF
      ENDIF is_there
!
!
   END SUBROUTINE conn_do_set
!
   SUBROUTINE conn_menu
!-                                                                      
!     Main menu for connectivity related operations                          
!+                                                                      
      USE discus_config_mod 
      USE crystal_mod 
      USE modify_mod
!
      USE doact_mod 
      USE learn_mod 
      USE class_macro_internal
      USE prompt_mod 
      IMPLICIT none 
!                                                                       
!                                                                       
      INTEGER, PARAMETER :: MIN_PARA = 4
      INTEGER maxw 
!                                                                       
      CHARACTER(5) befehl 
!     CHARACTER(50) prom 
      CHARACTER(LEN=LEN(PROMPT)) :: orig_prompt 
      CHARACTER(1024) line, zeile
      CHARACTER(LEN=1024), DIMENSION(MAX(MIN_PARA,MAXSCAT+1)) :: cpara ! (MAXSCAT) 
      INTEGER            , DIMENSION(MAX(MIN_PARA,MAXSCAT+1)) :: lpara ! (MAXSCAT)
      CHARACTER (LEN=256)  :: c_name   ! Connectivity name
      INTEGER              :: c_name_l ! connectivity name length
      INTEGER              :: ino      ! connectivity no
      INTEGER              :: iatom    ! atoms no for show
      INTEGER              :: itype    ! atomR type for recreate
      INTEGER lp, length, lbef 
      INTEGER indxg, ianz, iianz
      LOGICAL              :: long     ! make long output
      LOGICAL              :: lnew     ! Do not make new atom type
      LOGICAL lend
      REAL               , DIMENSION(MAX(MIN_PARA,MAXSCAT+1)) ::  werte ! (MAXSCAT) 
!                                                                       
      INTEGER len_str 
      LOGICAL str_comp 
      REAL       :: ran1
!                                                                       
      maxw = MAX(MIN_PARA,MAXSCAT+1)
      lend = .false. 
      CALL no_error 
      orig_prompt = prompt
      prompt = prompt (1:len_str (prompt) ) //'/conn' 
!                                                                       
      DO while (.not.lend) 
      CALL get_cmd (line, length, befehl, lbef, zeile, lp, prompt) 
      IF (ier_num.eq.0) then 
         IF (line /= ' '      .and. line(1:1) /= '#' .and. &
             line /= char(13) .and. line(1:1) /= '!'        ) THEN
!                                                                       
!     ----search for "="                                                
!                                                                       
            indxg = index (line, '=') 
            IF (indxg.ne.0.and.                                      &
                .not. (str_comp (befehl, 'echo', 2, lbef, 4) ) .and. &
                .not. (str_comp (befehl, 'syst', 2, lbef, 4) ) .and. &
                .not. (str_comp (befehl, 'help', 2, lbef, 4) .or.    &
                       str_comp (befehl, '?   ', 2, lbef, 4) ) ) then                                              
!                                                                       
!     ------evaluatean expression and assign the value to a variabble   
!                                                                       
               CALL do_math (line, indxg, length) 
            ELSE 
!                                                                       
!------ ----execute a macro file                                        
!                                                                       
               IF (befehl (1:1) .eq.'@') then 
                  IF (length.ge.2) then 
                     CALL file_kdo (line (2:length), length - 1) 
                  ELSE 
                     ier_num = - 13 
                     ier_typ = ER_MAC 
                  ENDIF 
!                                                                       
!     ----continues a macro 'continue'                                  
!                                                                       
               ELSEIF (str_comp (befehl, 'continue', 2, lbef, 8) ) then 
                  CALL macro_continue (zeile, lp) 
!                                                                       
!------ ----Echo a string, just for interactive check in a macro 'echo' 
!                                                                       
               ELSEIF (str_comp (befehl, 'echo', 2, lbef, 4) ) then 
                  CALL echo (zeile, lp) 
!                                                                       
!      ---Evaluate an expression, just for interactive check 'eval'     
!                                                                       
               ELSEIF (str_comp (befehl, 'eval', 2, lbef, 4) ) then 
                  CALL do_eval (zeile, lp) 
!                                                                       
!     ----exit 'exit'                                                   
!                                                                       
               ELSEIF (str_comp (befehl, 'exit', 2, lbef, 4) ) then 
                  lend = .true. 
!                                                                       
!     ----help 'help','?'                                               
!                                                                       
               ELSEIF (str_comp (befehl, 'help', 2, lbef, 4) .or.  &
                       str_comp (befehl, '?   ', 1, lbef, 4) ) then                                      
                  IF (str_comp (zeile, 'errors', 2, lp, 6) ) then 
                     lp = lp + 7 
                     CALL do_hel ('discus '//zeile, lp) 
                  ELSE 
                     lp = lp + 12 
                     CALL do_hel ('discus conn '//zeile, lp) 
                  ENDIF 
!                                                                       
!------- -Operating System Kommandos 'syst'                             
!                                                                       
               ELSEIF (str_comp (befehl, 'syst', 2, lbef, 4) ) then 
                  IF (zeile.ne.' ') then 
                     CALL do_operating (zeile (1:lp), lp) 
                  ELSE 
                     ier_num = - 6 
                     ier_typ = ER_COMM 
                  ENDIF 
!                                                                       
!------  -----waiting for user input                                    
!                                                                       
               ELSEIF (str_comp (befehl, 'wait', 3, lbef, 4) ) then 
                  CALL do_input (zeile, lp) 
!                                                                       
!     ----create a connectivity list 'create'                                     
!                                                                       
               ELSEIF (str_comp (befehl, 'create', 2, lbef, 6) ) then 
                  CALL create_connectivity
!                                                                       
!     ----delete a connectivity list 'delete'                                     
!                                                                       
               ELSEIF (str_comp (befehl, 'delete', 2, lbef, 6) ) then 
                  CALL deallocate_conn (conn_nmax)
!                                                                       
!     ----add a new connectivity definition       'add'
!                                                                       
               ELSEIF (str_comp (befehl, 'add', 2, lbef, 3) ) then 
                  CALL conn_do_set (code_add,zeile, lp) 
!                                                                       
!     ----remove an old    connectivity definition 'remove'                 
!                                                                       
               ELSEIF (str_comp (befehl, 'remove', 3, lbef, 6) ) then 
                  CALL conn_do_set (code_del,zeile, lp) 
!                                                                       
!     ----recreate a connectivity list 'recreate'                                     
!                                                                       
               ELSEIF (str_comp (befehl, 'recreate', 3, lbef, 8) ) then 
                  CALL get_params (zeile, ianz, cpara, lpara, maxw, length) 
                  IF(ier_num==0) THEN
                     itype  = 0
                     ino    = 0
                     c_name = ' '
                     IF(ianz==2) THEN
                        iianz = 1
                        lnew  = .false.
                        CALL get_iscat (iianz, cpara, lpara, werte, maxw, lnew)
                        IF(ier_num==0) THEN
                           itype = NINT(werte(1))
                           CALL del_params (1, ianz, cpara, lpara, maxw)
                           c_name = cpara(1)(1:lpara(1))
                           CALL ber_params (ianz, cpara, lpara, werte, maxw) 
                           IF(ier_num==0) THEN
                              ino = NINT(werte(1))
                              c_name = ' '
                           ELSEif(ier_num==-1 .AND. ier_typ==ER_FORT) THEN
                              CALL no_error   ! assume 
                           ENDIF
                           CALL recreate_connectivity(itype, ino, c_name)
                        ENDIF
                     ELSE
                        ier_num = -6
                        ier_typ = ER_COMM
                     ENDIF
                  ENDIF
!                                                                       
!     ----reset to no      connectivity definition 'reset'                 
!                                                                       
               ELSEIF (str_comp (befehl, 'reset', 3, lbef, 5) ) then 
                  CALL conn_do_set (code_res,zeile, lp) 
                  CALL deallocate_conn (conn_nmax)
!                                                                       
!     ----overwrite  a new connectivity definition 'set'                 
!                                                                       
               ELSEIF (str_comp (befehl, 'set', 2, lbef, 3) ) then 
                  CALL conn_do_set (code_set,zeile, lp) 
!                                                                       
!     ----show current parameters 'show'                                
!                                                                       
               ELSEIF (str_comp (befehl, 'show', 2, lbef, 4) ) then 
                  CALL get_params (zeile, ianz, cpara, lpara, maxw, length) 
                  IF ( ianz==0) THEN
                     CALL conn_show 
!                  CALL conn_test  For debug only
                  ELSE
                     IF (str_comp (cpara(1), 'connect', 3, lpara(1), 7) ) then
                        CALL del_params (1, ianz, cpara, lpara, maxw)
                        IF(str_comp (cpara(ianz), 'long',3, lpara(ianz), 4)) THEN
                           long = .true.
                           ianz = ianz - 1
                        ELSE
                           long = .false.
                        ENDIF
                        iianz = 1
                        CALL ber_params (iianz, cpara, lpara, werte, maxw) 
                        iatom = NINT(werte(1))
                        CALL del_params (1, ianz, cpara, lpara, maxw)
                        CALL ber_params (ianz, cpara, lpara, werte, maxw) 
                        IF(ier_num/=0) THEN
                           c_name_l = MIN(256,lpara(1))
                           c_name   = cpara(1)(1:c_name_l)
                           ino      = 0
                           CALL no_error
                        ELSE                                               ! Success set to value
                           ino = nint (werte (1) ) 
                           c_name   = ' '
                           c_name_l = 1
                        ENDIF
                        CALL get_connectivity_identity( cr_iscat(iatom), ino, c_name, c_name_l)
                        CALL do_show_connectivity ( iatom, ino, c_name, long)
                     ELSE 
                        ier_num = - 6 
                        ier_typ = ER_COMM 
                     ENDIF 
                  ENDIF 
!                                                                       
!     ----Perform bond switching 'switch'                 
!                                                                       
               ELSEIF (str_comp (befehl, 'switch', 2, lbef, 6) ) then 
                  iatom  = INT(ran1(idum)*cr_natoms) + 1
                  ino    = 1
                  c_name = 'c_first'
                  CALL do_bond_switch (iatom, ino, c_name) 
               ELSE 
                  ier_num = - 8 
                  ier_typ = ER_COMM 
               ENDIF 
            ENDIF 
         ENDIF 
      ENDIF 
      IF (ier_num.ne.0) THEN 
         CALL errlist 
         IF (ier_sta.ne.ER_S_LIVE) THEN 
            IF (lmakro .OR. lmakro_error) THEN  ! Error within macro or termination errror
               IF(sprompt /= prompt ) THEN
                  ier_num = -10
                  ier_typ = ER_COMM
                  ier_msg(1) = ' Error occured in connectivity menu'
                  prompt_status = PROMPT_ON 
                  prompt = orig_prompt
                  RETURN
               ELSE
                  CALL macro_close 
                  prompt_status = PROMPT_ON 
               ENDIF 
            ENDIF 
            IF (lblock) THEN 
               ier_num = - 11 
               ier_typ = ER_COMM 
               prompt_status = PROMPT_ON 
               prompt = orig_prompt
               RETURN 
            ENDIF 
            CALL no_error 
            lmakro_error = .FALSE.
            sprompt = ' '
         ENDIF 
      ENDIF 
      ENDDO 
      prompt = orig_prompt
!                                                                       
   END SUBROUTINE conn_menu
!
   SUBROUTINE conn_show
!-                                                                      
!     Show connectivity definitions
!+                                                                      
      USE discus_config_mod 
      USE crystal_mod 
      USE atom_name
      USE prompt_mod
      IMPLICIT none 
!
      INTEGER   :: is
      INTEGER   :: i
!
      exist_def: IF ( ALLOCATED(def_main)) THEN    ! Are there any definitions
        scats: DO is=0,maxscat                     ! Loop over all atom types
           IF ( .NOT. ASSOCIATED(def_main(is)%def_liste)) THEN  ! This type has no def.s
              CYCLE scats
           ENDIF
           def_temp => def_main(is)%def_liste
           WRITE(output_io, 1000) at_name(is)
           DO
              IF ( .NOT. ASSOCIATED(def_temp)) THEN  ! This type has no more def.s
                 CYCLE scats
              ENDIF
              WRITE(output_io, 2000) def_temp%valid_id, &
                  def_temp%def_name(1:def_temp%def_name_l), def_temp%valid_no,   &
                  (at_name  (def_temp%valid_types(i)),i=1,def_temp%valid_no)
!                 (cr_at_lis(def_temp%valid_types(i)),                                &
!                            def_temp%valid_types(i) ,i=1,def_temp%valid_no)
              WRITE(output_io, 2300) def_temp%intend_no,def_temp%def_rmin,&
                                                        def_temp%def_rmax
              def_temp => def_temp%def_next
           ENDDO
        ENDDO scats
      ELSE exist_def                               ! No def.s exist
         WRITE(output_io, 7000) 
      ENDIF exist_def
!
1000  FORMAT(' Central atom type       : ',a9)
2000  FORMAT('     Def.no; Name; No.of.types; Types : ',i4,1x, a,1x,i4,1x, &
             ': ',20(a9:,',',2x))
!            20(a4,'(',i4,')',2x))
2300  FORMAT('     Max neig, Bond length range', 4x,i8,2x,f8.4, 2x, f8.4)
7000  FORMAT(' No connectivity definitions set')
!
   END SUBROUTINE conn_show
!
!
   SUBROUTINE conn_test
!-                                                                      
!     Mainly used while developing code, tests the connectivity
!+                                                                      
      USE discus_config_mod 
      USE crystal_mod 
      IMPLICIT none 
!
      INTEGER    :: i
!
!
      IF ( ALLOCATED(at_conn) ) THEN
         atoms:DO i=1,cr_natoms
        IF ( ASSOCIATED(at_conn(i)%liste) ) THEN      ! If neighborhood was created
          hood_temp => at_conn(i)%liste               ! point to the first neighborhood
!         hood_head => at_conn(i)%liste
          DO WHILE ( ASSOCIATED(hood_temp) )          ! While there are further neighborhood
             temp => hood_temp%nachbar                    ! point to the first neighbor within current neigborhood
             head => hood_temp%nachbar
             head => at_conn(i)%liste%nachbar             ! head points to the first NEIGHBOR
             DO WHILE ( ASSOCIATED(temp) )               ! While there are further neighbors
               temp => temp%next                         ! Point to next neighbor
               head => temp                              ! also point to next neighbor
             END DO
             hood_temp => hood_temp%next_neighborhood     ! Point to next neighborhood
          END DO
        END IF
         ENDDO atoms
      ENDIF
!
   END SUBROUTINE conn_test
!
!
   SUBROUTINE get_connectivity_list (jatom, is1, ino, c_list, c_offs, natoms )
!-                                                                      
!     Get the list of neighbors for central atom jatom of type is1
!+                                                                      
      USE discus_config_mod 
      USE crystal_mod 
      IMPLICIT none 
!
      INTEGER, INTENT(IN)  :: jatom   ! central atom number
      INTEGER, INTENT(IN)  :: is1     ! central atom type
      INTEGER, INTENT(INOUT)  :: ino     ! Connectivity def. no.
      CHARACTER(LEN=256)   :: c_name  ! Connectivity name
      INTEGER, DIMENSION(:), ALLOCATABLE, INTENT(OUT) :: c_list    ! Size of array c_list 
      INTEGER, DIMENSION(:,:), ALLOCATABLE, INTENT(OUT) :: c_offs ! Offsets from periodic boundary
      INTEGER, INTENT(OUT) :: natoms  ! number of atoms in connectivity list
!
      INTEGER    :: i,k
!
      natoms = 0
!
!
      IF ( ALLOCATED(at_conn) ) THEN
         i = jatom 
        IF ( ASSOCIATED(at_conn(i)%liste) ) THEN      ! If neighborhood was created
          hood_temp => at_conn(i)%liste               ! point to the first neighborhood
!         hood_head => at_conn(i)%liste
          DO WHILE ( ASSOCIATED(hood_temp) )          ! While there are further neighborhood
             temp => hood_temp%nachbar                    ! point to the first neighbor within current neigborhood
             IF ( hood_temp%neigh_type == ino  .OR. &
                  hood_temp%conn_name  == c_name   ) THEN   ! This is the right neighborhood
                ino    = hood_temp%neigh_type         ! Return actual number and name
                c_name = hood_temp%conn_name
                natoms = hood_temp%natoms
                IF(ALLOCATED(c_list)) THEN
!                  IF(UBOUND(c_list).lt.natoms) THEN
                      DEALLOCATE(c_list)
                      ALLOCATE(c_list(1:natoms))
!                  ENDIF
                ELSE
                   ALLOCATE(c_list(1:natoms))
                ENDIF
                IF(ALLOCATED(c_offs)) THEN
!                  IF(UBOUND(c_offs).lt.natoms) THEN
                      DEALLOCATE(c_offs)
                      ALLOCATE(c_offs(1:3,1:natoms))
!                  ENDIF
                ELSE
                   ALLOCATE(c_offs(1:3,1:natoms))
                ENDIF
                c_list = 0   ! clear connectivity list
                k = 0
                DO WHILE ( ASSOCIATED(temp) )               ! While there are further neighbors
                    k         = k+ 1
                    c_list(k) = temp%atom_number
                    c_offs(1,k) = temp%offset(1)
                    c_offs(2,k) = temp%offset(2)
                    c_offs(3,k) = temp%offset(3)
                  temp => temp%next                         ! Point to next neighbor
                END DO
                RETURN                                      ! End of connectivity list
             ENDIF
             hood_temp => hood_temp%next_neighborhood     ! Point to next neighborhood
          END DO
        END IF
      ENDIF
!
   END SUBROUTINE get_connectivity_list
!
!
   SUBROUTINE get_connectivity_identity (is1, work_id, work_name, work_name_l)
!-                                                                      
!     Get the identity of a connectivity from central atom and number or name
!+                                                                      
      USE discus_config_mod 
      USE crystal_mod 
      IMPLICIT none 
!
!
      INTEGER,            INTENT(IN)      :: is1        ! central atom type
      INTEGER,            INTENT(INOUT)   :: work_id    ! Connectivity def. no.
      CHARACTER(LEN=256), INTENT(INOUT)   :: work_name  ! Connectivity name
      INTEGER           , INTENT(INOUT)   :: work_name_l! Connectivity name length
!
      IF ( ALLOCATED(def_main) ) THEN
         is_there: IF ( ASSOCIATED(def_main(is1)%def_liste) ) THEN  ! A list of definitions exists
            def_head => def_main(is1)%def_liste
            def_temp => def_main(is1)%def_liste
            search: DO                                           ! search for working definition
               IF ( .NOT. ASSOCIATED(def_temp)) THEN             ! target is not associated ERROR
                  ier_num = -109
                  ier_typ = ER_APPL
                  RETURN
               ENDIF
               IF ( work_id   == def_temp%valid_id  .OR. &
                    work_name == def_temp%def_name       ) THEN  ! Found working definition
                  work_id     = def_temp%valid_id                ! Make sure ID matches
                  work_name   = def_temp%def_name                ! Make sure name matches
                  work_name_l = def_temp%def_name_l              ! Make sure name matches
                  EXIT search
               ENDIF
               def_head => def_temp
               def_temp => def_temp%def_next
            ENDDO search
         ELSE
            ier_num = -109
            ier_typ = ER_APPL
         ENDIF is_there
      ELSE
         ier_num = -110
         ier_typ = ER_APPL
      ENDIF
!
   END SUBROUTINE get_connectivity_identity
!
!
   INTEGER FUNCTION get_connectivity_numbers (is1)
!-                                                                      
!     Return the number of connectivities defined for an atom type
!+                                                                      
      USE discus_config_mod 
      USE crystal_mod 
      IMPLICIT none 
!
      INTEGER,            INTENT(IN)      :: is1        ! central atom type
!
      INTEGER :: numbers
!
      numbers = 0
      IF ( ALLOCATED(def_main) ) THEN
         is_there: IF ( ASSOCIATED(def_main(is1)%def_liste) ) THEN  ! A list of definitions exists
            numbers = def_main(is1)%def_number
         ENDIF is_there
      ELSE
         ier_num = -110
         ier_typ = ER_APPL
      ENDIF
!
      get_connectivity_numbers = numbers   ! assign return value
!
   END FUNCTION get_connectivity_numbers
!
!
   SUBROUTINE do_show_connectivity ( iatom, idef, c_name, long )
!-                                                                      
!     Shows the connectivity no. idef around atom no iatom
!+                                                                      
      USE crystal_mod
      USE atom_name
      USE modify_mod
      USE metric_mod
      USE param_mod 
      USE prompt_mod 
      USE lib_f90_allocate_mod
      IMPLICIT none 
!                                                                       
!
      INTEGER          , INTENT(IN)    :: iatom
      INTEGER          , INTENT(INOUT) :: idef
      CHARACTER(LEN=*) , INTENT(IN)    :: c_name
      LOGICAL          , INTENT(IN)    :: long
!
      INTEGER, PARAMETER         :: maxw = 2000
!
      CHARACTER (LEN=9)          :: at_name_d
      CHARACTER (LEN=32)         :: c_property
      INTEGER                    :: is1
      INTEGER, DIMENSION(:), ALLOCATABLE :: c_list
      INTEGER, DIMENSION(:,:), ALLOCATABLE :: c_offs
      INTEGER                    :: natoms
!                                                                       
      INTEGER                    :: i, j
      INTEGER                    :: length
      INTEGER                    :: n_res
      REAL   , DIMENSION(3)      :: u, v
      REAL                       :: distance
!
      is1 = cr_iscat(iatom)
      u   = cr_pos(:,iatom)
      CALL get_connectivity_list (iatom, is1, idef, c_list, c_offs, natoms )
!
      WRITE(output_io,1000) iatom, at_name(is1), idef,c_name(1:LEN_TRIM(c_name)), natoms
      IF ( natoms > 0 ) THEN
        DO j=1,(natoms-1)/6+1
           WRITE(output_io, 1100) (c_list(i),i=(j-1)*6+1, MIN((j-1)*6 + 6,natoms))
        ENDDO
      ELSE
         WRITE(output_io, 1200)
      ENDIF
      IF( natoms > MAXPAR_RES) THEN
        n_res = MAX(natoms,MAXPAR_RES,CHEM_MAX_NEIG)
        CALL alloc_param(n_res)
        MAXPAR_RES = n_res
      ENDIF
      IF ( natoms <= MAXPAR_RES ) THEN
         res_para(0) = FLOAT(natoms)
         res_para(1:natoms) = FLOAT(c_list(1:natoms))
      ENDIF
!
      IF(long) THEN
         DO j= 1,natoms
            i = c_list(j)
            at_name_d = at_name(cr_iscat(i))
            CALL char_prop_1 (c_property, cr_prop (i), length) 
            WRITE (output_io, 3010) at_name_d, cr_pos (1, i), cr_pos (2,&
            i), cr_pos (3, i), cr_dw (cr_iscat (i) ), c_property (1:    &
            length)
            v(:) = cr_pos(:,i) + c_offs(:,j)
            distance = do_blen(.TRUE., u,v)
            WRITE (output_io, 3020) c_offs(:,j), distance
         ENDDO
      ENDIF
!
      IF(ALLOCATED(c_list)) THEN
         DEALLOCATE(c_list)
      ENDIF
!
1000  FORMAT( ' Connectivity for atom No. ',I6,' of type ', &
             a9,' No : ',i4,1x,a,/,                         &
              '      Neighbor number:', i3)
1100  FORMAT( '      Neighbors are        ',20(i6:,2x))
1200  FORMAT( '      Atom has no neighbours')
3010  FORMAT(1x,a9,3(2x,f12.6),4x,f10.6,2x,a) 
3020  FORMAT( 3x  ,3(8x,i6   ),9x,f12.6    ) 
!
      END SUBROUTINE do_show_connectivity 
!
   SUBROUTINE do_bond_switch (jatom, ino, c_name)
!-                                                                      
!     Get the list of neighbors for central atom jatom of type is1
!+                                                                      
   USE discus_config_mod 
   USE crystal_mod 
!
   IMPLICIT none 
!
   INTEGER           , INTENT(IN)     :: jatom   ! central atom number
   INTEGER           , INTENT(INOUT)  :: ino     ! Connectivity def. no.
   CHARACTER(LEN=256), INTENT(INOUT)  :: c_name  ! Connectivity name
!
   INTEGER                              :: maxw    ! Size of array c_list 
   INTEGER, DIMENSION(:),   ALLOCATABLE :: c_list  ! List of all neighbors 
   INTEGER, DIMENSION(:,:), ALLOCATABLE :: c_offs  ! Offsets from periodic boundary
   INTEGER, DIMENSION(:),   ALLOCATABLE :: s_list  ! List of all neighbors 
   INTEGER, DIMENSION(:,:), ALLOCATABLE :: s_offs  ! Offsets from periodic boundary
   INTEGER, DIMENSION(:),   ALLOCATABLE :: j_list  ! List of all neighbors 
   INTEGER, DIMENSION(:,:), ALLOCATABLE :: j_offs  ! Offsets from periodic boundary
   INTEGER, DIMENSION(:),   ALLOCATABLE :: k_list  ! List of all neighbors 
   INTEGER, DIMENSION(:,:), ALLOCATABLE :: k_offs  ! Offsets from periodic boundary
   INTEGER                              :: c_natoms  ! number of atoms in connectivity list
   INTEGER                              :: s_natoms  ! number of atoms in connectivity list
   INTEGER                              :: j_natoms  ! number of atoms in connectivity list
   INTEGER                              :: k_natoms  ! number of atoms in connectivity list
   INTEGER, DIMENSION(:)  , ALLOCATABLE :: temp_list !ffsets from periodic boundary
!
   TYPE (NEIGHBORHOOD), POINTER       :: hood_j
   TYPE (NEIGHBORHOOD), POINTER       :: hood_k
   INTEGER    :: c_neig, s_neig, c_ex, s_ex
   INTEGER, DIMENSION(3) :: t_offs, in_offs
   INTEGER               :: t_ex, in_ex, in_ref
   INTEGER    :: katom, j_ex, k_ex
   INTEGER    :: i,k
   INTEGER :: j_in_j, k_in_k
   LOGICAL :: j_ex_in_s_list
   LOGICAL :: k_ex_in_c_list
   REAL       :: ran1
!
   NULLIFY(hood_j)
   NULLIFY(hood_k)
   c_natoms = 0
!
!
   IF ( ALLOCATED(at_conn) ) THEN
      CALL get_connect_pointed(hood_central, jatom, ino, c_name, c_list, c_offs, c_natoms)
! We should have found a central atom and its connectivity list.
! Randomly pick a neighbor atom
      c_neig = INT(ran1(idum)*c_natoms) + 1
      katom  = c_list(c_neig) 
      CALL get_connect_pointed(hood_second, katom, ino, c_name, s_list, s_offs, s_natoms)
!
      s_neig = 0                                          ! Central not yet found
search_c: DO i=1, s_natoms
         IF(s_list(i) == jatom) THEN
            s_neig = i
            EXIT search_c
         ENDIF
      ENDDO search_c
      IF(s_neig == 0) THEN
         write(*,*) ' CENTRAL atom is NOT a neighbor to second', jatom, c_list(c_neig)
!        ier_num = -6
!        ier_typ = ER_FORT
!write(*,*) ' Neigbors central ',jatom         , c_neig, (c_list(i),i=1,c_natoms)
!write(*,*) ' Neigbors second  ',c_list(c_neig), s_neig, (s_list(i),i=1,s_natoms)
         DEALLOCATE(s_list)
         DEALLOCATE(c_list)
         DEALLOCATE(s_offs)
         DEALLOCATE(c_offs)
         RETURN
      ENDIF
!
!write(*,*) ' Neigbors central ',jatom         , c_neig, (c_list(i),i=1,c_natoms)
!write(*,*) ' Neigbors second  ',c_list(c_neig), s_neig, (s_list(i),i=1,s_natoms)
      c_ex = MOD(INT(ran1(idum)*(c_natoms-1)) + (c_neig), c_natoms ) + 1
      s_ex = MOD(INT(ran1(idum)*(s_natoms-1)) + (s_neig), s_natoms ) + 1
      j_ex = c_list(c_ex)
      k_ex = s_list(s_ex)
!
      j_ex_in_s_list = .FALSE.
      DO i=1, s_natoms
         IF(s_list(i) == j_ex) THEN
            j_ex_in_s_list = .TRUE.
         ENDIF
      ENDDO
      k_ex_in_c_list = .FALSE.
      DO i=1, c_natoms
         IF(c_list(i) == k_ex) THEN
            k_ex_in_c_list = .TRUE.
         ENDIF
      ENDDO
if(j_ex_in_s_list .OR. k_ex_in_c_list) THEN
   write(*,*) 'EXCHANGE WOULD PRODUCE DOUBLE PARTNER '
!ier_num = -6
!ier_typ = ER_FORT
!         DEALLOCATE(s_list)
!         DEALLOCATE(c_list)
!         DEALLOCATE(s_offs)
!         DEALLOCATE(c_offs)
!         RETURN
ENDIF
if(j_ex == k_ex) then
write(*,*) 'Trying to exchange identical neighbors'
!ier_num = -6
!ier_typ = ER_FORT
!         DEALLOCATE(s_list)
!         DEALLOCATE(c_list)
!         DEALLOCATE(s_offs)
!         DEALLOCATE(c_offs)
!         RETURN
ENDIF

      IF(.NOT.(j_ex_in_s_list .OR. k_ex_in_c_list .OR. j_ex == k_ex )) THEN ! SUCCESS
!write(*,*) ' Exchange central ', c_ex, c_list(c_ex)
!write(*,*) ' Exchange second  ', s_ex, s_list(s_ex)
!
!     Get neighbors for the atoms that will be exchanged
      CALL get_connect_pointed(hood_j, j_ex, ino, c_name, j_list, j_offs, j_natoms)
      CALL get_connect_pointed(hood_k, k_ex, ino, c_name, k_list, k_offs, k_natoms)
      j_in_j = 0                                          ! Central not yet found
search_k: DO i=1, j_natoms
         IF(j_list(i) == jatom) THEN
            j_in_j = i
            EXIT search_k
         ENDIF
      ENDDO search_k
      k_in_k = 0                                          ! Central not yet found
search_j: DO i=1, k_natoms
         IF(k_list(i) == katom) THEN
            k_in_k = i
            EXIT search_j
         ENDIF
      ENDDO search_j
!write(*,*) ' JATOM IS nei.no ', jatom, j_in_j
!write(*,*) ' KATOM IS nei.no ', katom, k_in_k
!
! now do the exchange
!
      in_ref     = s_list(s_ex)    ! Find this partner
      in_ex      = c_list(c_ex)    ! store this atom number instead of old
      in_offs(:) = c_offs(:,c_ex)  ! store this offset instead of old
      CALL do_exchange(hood_second%nachbar, in_ref, in_ex, in_offs, t_ex, t_offs)
      in_ref     = c_list(c_ex)    ! Find this partner
      in_ex      = t_ex            ! store this atom number instead of old
      in_offs(:) = t_offs(:)       ! store this offset instead of old
      CALL do_exchange(hood_central%nachbar, in_ref, in_ex, in_offs, t_ex, t_offs)
      in_ref     = jatom           ! Find this partner
      in_ex      = katom           ! store this atom number instead of old
      in_offs(:) = k_offs(:,k_in_k)! store this offset instead of old
      CALL do_exchange(hood_j%nachbar, in_ref, in_ex, in_offs, t_ex, t_offs)
      in_ref     = katom           ! Find this partner
      in_ex      = jatom           ! store this atom number instead of old
      in_offs(:) = j_offs(:,j_in_j)! store this offset instead of old
      CALL do_exchange(hood_k%nachbar, in_ref, in_ex, in_offs, t_ex, t_offs)
!
! JUST TO DEBUG TEST NEIGHBORHOODS
!      allocate(temp_list(c_natoms))
!!DBG
!      sw_central => hood_central%nachbar       ! point to the first neighbor within current neigborhood
!      temp_list(:) = 0
!      k = 0
! check_c_ex: DO WHILE(ASSOCIATED(sw_central))
!         k = k + 1
!         temp_list(k) = sw_central%atom_number
!         sw_central => sw_central%next                         ! Point to next neighbor
!      ENDDO  check_c_ex
!write(*,*) ' Neigbors central ',jatom         , c_neig, (temp_list(i),i=1,c_natoms)
!      sw_second => hood_second%nachbar       ! point to the first neighbor within current neigborhood
!      temp_list(:) = 0
!      k = 0
! check_s_ex: DO WHILE(ASSOCIATED(sw_second))
!         k = k + 1
!         temp_list(k) = sw_second%atom_number
!         sw_second => sw_second%next                         ! Point to next neighbor
!      ENDDO  check_s_ex
!write(*,*) ' Neigbors second  ',c_list(c_neig), s_neig, (temp_list(i),i=1,s_natoms)
!      sw_second => hood_j%nachbar       ! point to the first neighbor within current neigborhood
!      temp_list(:) = 0
!      k = 0
! check_j_ex: DO WHILE(ASSOCIATED(sw_second))
!         k = k + 1
!         temp_list(k) = sw_second%atom_number
!         sw_second => sw_second%next                         ! Point to next neighbor
!      ENDDO  check_j_ex
!write(*,*) ' Neigbors exch 1  ',j_ex          , j_in_j, (temp_list(i),i=1,s_natoms)
!      sw_second => hood_k%nachbar       ! point to the first neighbor within current neigborhood
!      temp_list(:) = 0
!      k = 0
! check_k_ex: DO WHILE(ASSOCIATED(sw_second))
!         k = k + 1
!         temp_list(k) = sw_second%atom_number
!         sw_second => sw_second%next                         ! Point to next neighbor
!      ENDDO  check_k_ex
!write(*,*) ' Neigbors exch 2  ',k_ex          , k_in_k, (temp_list(i),i=1,s_natoms)
!
!
      ENDIF
   ENDIF
   DEALLOCATE(s_list)
   DEALLOCATE(c_list)
   DEALLOCATE(s_offs)
   DEALLOCATE(c_offs)
   NULLIFY(hood_j)
   NULLIFY(hood_k)
!
   END SUBROUTINE do_bond_switch
!
   SUBROUTINE get_connect_pointed(hood_p, jatom, ino, c_name, c_list, c_offs, c_natoms)
!
   IMPLICIT NONE
!
!
   TYPE (NEIGHBORHOOD)    , POINTER                  :: hood_p
   INTEGER                             , INTENT(IN)  :: jatom   ! central atom number
   INTEGER                             , INTENT(INOUT)  :: ino     ! Connectivity def. no.
   CHARACTER(LEN=256)                  , INTENT(INOUT)  :: c_name  ! Connectivity name
   INTEGER, DIMENSION(:),   ALLOCATABLE, INTENT(OUT) :: c_list  ! List of all neighbors 
   INTEGER, DIMENSION(:,:), ALLOCATABLE, INTENT(OUT) :: c_offs  ! Offsets from periodic boundary
   INTEGER                             , INTENT(OUT) :: c_natoms  ! number of neigbor atoms
!
   TYPE (NEIGHBORS), POINTER  :: p_atoms
   INTEGER :: i, k
!
   i = jatom
   IF(ASSOCIATED(at_conn(i)%liste)) THEN
      hood_p => at_conn(i)%liste                 ! point to the first neighborhood
search1:  DO WHILE ( ASSOCIATED(hood_p) )        ! While there are further neighborhood
         p_atoms => hood_p%nachbar               ! point to the first neighbor within current neigborhood
         IF ( hood_p%neigh_type == ino  .OR. &
            hood_p%conn_name  == c_name   ) THEN ! This is the right neighborhood
            ino    = hood_p%neigh_type           ! Return actual number and name
            c_name = hood_p%conn_name
            c_natoms = hood_p%natoms             ! Store number of neigboring atoms
            IF(ALLOCATED(c_list)) THEN           ! Just in case, if the list exists already
               DEALLOCATE(c_list)
               ALLOCATE(c_list(1:c_natoms))
            ELSE
               ALLOCATE(c_list(1:c_natoms))
            ENDIF
            IF(ALLOCATED(c_offs)) THEN
               DEALLOCATE(c_offs)
               ALLOCATE(c_offs(1:3,1:c_natoms))
            ELSE
               ALLOCATE(c_offs(1:3,1:c_natoms))
            ENDIF
            c_list = 0                           ! clear connectivity list
            k = 0
            DO WHILE ( ASSOCIATED(p_atoms) )     ! While there are further neighbors
               k         = k+ 1
               c_list(k) = p_atoms%atom_number   ! Add atoms
               c_offs(1,k) = p_atoms%offset(1)   ! and relative offsets
               c_offs(2,k) = p_atoms%offset(2)
               c_offs(3,k) = p_atoms%offset(3)
               p_atoms => p_atoms%next           ! Point to next neighbor
            END DO
            EXIT search1                         ! End of connectivity list
         ENDIF
         hood_p => hood_p%next_neighborhood      ! Point to next neighborhood
      END DO search1                             ! end of search central atom
   ENDIF
!
   END SUBROUTINE get_connect_pointed
!
   SUBROUTINE  do_exchange(hood_start, in_ref, in_ex, in_offs, t_ex, t_offs)
!
   IMPLICIT NONE
   TYPE (NEIGHBORS), POINTER                    :: hood_start
   INTEGER                        , INTENT(IN ) :: in_ref  ! Reference atom
   INTEGER                        , INTENT(IN ) :: in_ex   ! input exchange partner
   INTEGER, DIMENSION(3         ) , INTENT(IN ) :: in_offs ! Input offsets from periodic boundary
   INTEGER                        , INTENT(OUT) :: t_ex    ! Output echange partner
   INTEGER, DIMENSION(3         ) , INTENT(OUT) :: t_offs  ! Output offsets from periodic boundary
!
   TYPE (NEIGHBORS), POINTER  :: p_atoms
!
   p_atoms => hood_start               ! point to the first neighbor within current neigborhood
search_s_ex: DO WHILE(ASSOCIATED(p_atoms))
      IF(p_atoms%atom_number == in_ref      ) THEN ! Found second exchange partner
         t_ex                = p_atoms%atom_number
         t_offs(:)           = p_atoms%offset(:)
         p_atoms%atom_number = in_ex
         p_atoms%offset(:)   = in_offs(:)
         EXIT search_s_ex
      ENDIF
      p_atoms => p_atoms%next           ! Point to next neighborhood
   ENDDO search_s_ex
   NULLIFY(p_atoms)
   END SUBROUTINE  do_exchange
!
SUBROUTINE conn_update(isel, shift)
!
IMPLICIT NONE
!
INTEGER              , INTENT(IN) :: isel
REAL   , DIMENSION(3), INTENT(IN) :: shift
!
CHARACTER(LEN=256)                   :: c_name  ! Connectivity name
INTEGER, DIMENSION(:),   ALLOCATABLE :: c_list  ! List of all neighbors 
INTEGER, DIMENSION(:,:), ALLOCATABLE :: c_offs  ! Offsets from periodic boundary
CHARACTER(LEN=256)                   :: j_name  ! Connectivity name
INTEGER, DIMENSION(:),   ALLOCATABLE :: j_list  ! List of all neighbors 
INTEGER, DIMENSION(:,:), ALLOCATABLE :: j_offs  ! Offsets from periodic boundary
INTEGER :: c_natoms
INTEGER :: j_natoms
INTEGER :: ino
INTEGER :: i, j
INTEGER :: iatom
INTEGER :: is
TYPE (NEIGHBORHOOD), POINTER         :: hood_c
TYPE (NEIGHBORHOOD), POINTER         :: hood_j
   TYPE (NEIGHBORS), POINTER         :: p_atoms
!
NULLIFY(hood_c)
NULLIFY(hood_j)
!
ino = 0
IF(ASSOCIATED(at_conn(isel)%liste)) THEN     ! A connectivity list has been created
   is = cr_iscat(isel) 
   IF(ASSOCIATED(def_main(is)%def_liste)) THEN  ! This type has a definition
      def_temp => def_main(is)%def_liste
search_defs:      DO WHILE (ASSOCIATED(def_temp))           ! There are definitions to follow
         c_name = def_temp%def_name(1:def_temp%def_name_l)
         CALL get_connect_pointed(hood_c, isel, ino, c_name, c_list, c_offs, c_natoms)
         DO i=1,c_natoms                          ! Update all offsets
            c_offs(:,i) = c_offs(:,i) + shift(:)
         ENDDO
         p_atoms => hood_c%nachbar
         i = 1
         DO WHILE(ASSOCIATED(p_atoms))            ! Place into structure
            IF(p_atoms%atom_number == c_list(i)) THEN
               p_atoms%offset(:) = c_offs(:,i)
            ENDIF
            i = i + 1
            p_atoms => p_atoms%next
         ENDDO
         def_temp => def_temp%def_next
      ENDDO search_defs
   ENDIF
!
!  Loop over all atoms, and find out if atom isel is a neighbor to any, if so update
!  Might have to be replaced by a connectivity list that indicates for a given atom
!  which other atoms have this listed as neighbor....
   DO iatom = 1, cr_natoms
      IF(ASSOCIATED(at_conn(iatom)%liste)) THEN     ! A connectivity list has been created
         is = cr_iscat(iatom) 
         IF(ASSOCIATED(def_main(is)%def_liste)) THEN  ! This type has a definition
            def_temp => def_main(is)%def_liste
search_def2:DO WHILE (ASSOCIATED(def_temp))           ! There are definitions to follow
               j_name = def_temp%def_name(1:def_temp%def_name_l)
               CALL get_connect_pointed(hood_j, iatom, ino, j_name, j_list, j_offs, j_natoms)
               p_atoms => hood_j%nachbar
search_neig:   DO WHILE(ASSOCIATED(p_atoms))            ! Place into structure
                  IF(p_atoms%atom_number == isel     ) THEN
                     p_atoms%offset(:) = p_atoms%offset(:) -shift(:)
                     EXIT search_neig
                  ENDIF
                  p_atoms => p_atoms%next
               ENDDO search_neig
               def_temp => def_temp%def_next
            ENDDO search_def2
         ENDIF
      ENDIF
   ENDDO
ENDIF
IF(ALLOCATED(c_list)) DEALLOCATE(c_list)
IF(ALLOCATED(c_offs)) DEALLOCATE(c_offs)
IF(ALLOCATED(j_list)) DEALLOCATE(j_list)
IF(ALLOCATED(j_offs)) DEALLOCATE(j_offs)
NULLIFY(hood_c)
NULLIFY(hood_j)
!
!
END SUBROUTINE conn_update
!
END MODULE conn_mod
