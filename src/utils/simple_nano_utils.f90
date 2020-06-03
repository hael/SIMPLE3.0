module simple_nano_utils
  use simple_image,    only : image
  use simple_binimage, only : binimage
  use simple_rnd
  use simple_math
  use simple_defs ! singleton
  use simple_atoms,    only : atoms
  implicit none

  public :: kabsch, read_pdb2matrix, write_matrix2pdb, find_couples
  private


  interface kabsch
      module procedure kabsch_sp, kabsch_dp
  end interface kabsch

  interface read_pdb2matrix
      module procedure read_pdb2matrix_sp, read_pdb2matrix_dp
  end interface read_pdb2matrix

  interface find_couples
      module procedure find_couples_sp, find_couples_dp
  end interface find_couples

contains

  ! My implementation of the Matlab Kabsch algorithm
  ! source: https://au.mathworks.com/matlabcentral/fileexchange/25746-kabsch-algorithm
  ! Kabsch is for registering two pairs of 3D coords such that the RMSD
  ! is minimised
  subroutine kabsch_sp(points_P, points_Q, U, r, lrms)
     real(sp), intent(inout) :: points_P(:,:), points_Q(:,:) ! set of points to register
     integer, parameter      :: D = 3  !space dimension
     real(sp), intent(inout) :: U(D,D) !rotation matrix
     real(sp), intent(inout) :: r(D)   !translation
     real(sp), intent(inout) :: lrms   !RMSD of registered points
     real(sp), allocatable   :: m(:), Pdm(:,:), Diff(:,:), Diff_divided(:,:)
     integer  :: i, j, N
     real(sp) :: centroid_P(D), centroid_Q(D), C(D,D), w(D),v(D,D), Id(D,D)
     if(size(points_P,dim=1) /= D  .or. size(points_Q,dim=1) /= D) then
       write(logfhandle,*) 'WORNG input dims'
       stop
     elseif(size(points_P, dim = 2) /= size(points_Q, dim =2)) then
       write(logfhandle,*) 'Have to have same nb of points!'
       stop
     endif
     N = size(points_P, dim = 2)
     allocate(m(N), source = 1./real(N))
     ! translation
     centroid_P = sum(points_P(:,:), dim = 2)/real(N)
     centroid_Q = sum(points_Q(:,:), dim = 2)/real(N)
     do i = 1, N
         points_P(:,i) = points_P(:,i)-centroid_P(:)
     enddo
     do i = 1, N
         points_Q(:,i) = points_Q(:,i)-centroid_Q(:)
     enddo
     ! computation of the covariance matrix
     allocate(Pdm(D,N), source = 0.)
     do i = 1, N
         Pdm(:,i) = m(i)*points_P(:,i)
     enddo
     C = matmul(Pdm, transpose(points_Q)) !covariance matrix of the coords
     ! svd
     call svdcmp(C,w,v)
     ! identity matrix
     Id(:,:) = 0.
     do i = 1, D
         do j = 1, D
           if(i==j)  Id(i,j) = 1.
         enddo
     enddo
     if(det(matmul(C,transpose(v)),D,-1) < 0.) Id(2,2) = -1.
     U = matmul(matmul(v,Id),transpose(C))
     r = centroid_Q - matmul(U,centroid_P)
     allocate(Diff(D,N), source = 0.)
     Diff = matmul(U,points_P)-points_Q
     lrms = 0.
     do i = 1, N
         lrms = lrms + dot_product(m(i)*Diff(:,i),Diff(:,i))
     enddo
     lrms = sqrt(lrms)
   contains
     ! For calculating the determinant of a matrix
     ! source: https://rosettacode.org/wiki/Determinant_and_permanent#Fortran
     recursive function det(a,n,permanent) result(accumulation)
       ! setting permanent to 1 computes the permanent.
       ! setting permanent to -1 computes the determinant.
       integer, intent(in) :: n, permanent
       real,    intent(in) :: a(n,n)
       real    :: b(n-1,n-1),accumulation
       integer :: i, sgn
       if (n .eq. 1) then
         accumulation = a(1,1)
       else
         accumulation = 0
         sgn = 1
         do i=1, n
           b(:, :(i-1)) = a(2:, :i-1)
           b(:, i:) = a(2:, i+1:)
           accumulation = accumulation + sgn * a(1, i) * det(b, n-1, permanent)
           sgn = sgn * permanent
         enddo
       endif
     end function det
  end subroutine kabsch_sp

  ! My implementation of the Matlab Kabsch algorithm
  ! source: https://au.mathworks.com/matlabcentral/fileexchange/25746-kabsch-algorithm
  ! Kabsch is for registering two pairs of 3D coords such that the RMSD
  ! is minimised
  subroutine kabsch_dp(points_P, points_Q, U, r, lrms)
     real(dp), intent(inout) :: points_P(:,:), points_Q(:,:) ! set of points to register
     integer,  parameter     :: D = 3  !space dimension
     real(dp), intent(inout) :: U(D,D) !rotation matrix
     real(dp), intent(inout) :: r(D)   !translation
     real(dp), intent(inout) :: lrms   !RMSD of registered points
     real(dp), allocatable   :: m(:), Pdm(:,:), Diff(:,:), Diff_divided(:,:)
     integer  :: i, j, N
     real(dp) :: centroid_P(D), centroid_Q(D), C(D,D), w(D),v(D,D), Id(D,D)
     if(size(points_P,dim=1) /= D  .or. size(points_Q,dim=1) /= D) then
       write(logfhandle,*) 'WORNG input dims'
       stop
     elseif(size(points_P, dim = 2) /= size(points_Q, dim =2)) then
       write(logfhandle,*) 'Have to have same nb of points!'
       stop
     endif
     N = size(points_P, dim = 2)
     allocate(m(N), source = real(1./real(N),dp))
     ! translation
     centroid_P = sum(points_P(:,:), dim = 2)/real(N)
     centroid_Q = sum(points_Q(:,:), dim = 2)/real(N)
     do i = 1, N
         points_P(:,i) = points_P(:,i)-centroid_P(:)
     enddo
     do i = 1, N
         points_Q(:,i) = points_Q(:,i)-centroid_Q(:)
     enddo
     ! computation of the covariance matrix
     allocate(Pdm(D,N), source = 0.d0)
     do i = 1, N
         Pdm(:,i) = m(i)*points_P(:,i)
     enddo
     C = matmul(Pdm, transpose(points_Q)) !covariance matrix of the coords
     ! svd
     call svdcmp(C,w,v)
     ! identity matrix
     Id(:,:) = 0.
     do i = 1, D
         do j = 1, D
           if(i==j)  Id(i,j) = 1.
         enddo
     enddo
     if(det(real(matmul(C,transpose(v)),sp),D,-1) < 0.) Id(2,2) = -1.
     U = matmul(matmul(v,Id),transpose(C))
     r = centroid_Q - matmul(U,centroid_P)
     allocate(Diff(D,N), source = 0.d0)
     Diff = matmul(U,points_P)-points_Q
     lrms = 0.d0
     do i = 1, N
         lrms = lrms + dot_product(m(i)*Diff(:,i),Diff(:,i))
     enddo
     lrms = sqrt(lrms)
   contains
     ! For calculating the determinant of a matrix
     ! source: https://rosettacode.org/wiki/Determinant_and_permanent#Fortran
     recursive function det(a,n,permanent) result(accumulation)
       ! setting permanent to 1 computes the permanent.
       ! setting permanent to -1 computes the determinant.
       integer, intent(in) :: n, permanent
       real,    intent(in) :: a(n,n)
       real    :: b(n-1,n-1),accumulation
       integer :: i, sgn
       if (n .eq. 1) then
         accumulation = a(1,1)
       else
         accumulation = 0
         sgn = 1
         do i=1, n
           b(:, :(i-1)) = a(2:, :i-1)
           b(:, i:) = a(2:, i+1:)
           accumulation = accumulation + sgn * a(1, i) * det(b, n-1, permanent)
           sgn = sgn * permanent
         enddo
       endif
     end function det
  end subroutine kabsch_dp

  ! This subroutine takes in input a pdbfile and saves its
  ! coordinates onto matrix
  subroutine read_pdb2matrix_sp(pdbfile, matrix)
    use simple_fileio, only: fname2ext
    character(len=*),  intent(in)    :: pdbfile
    real, allocatable, intent(inout) :: matrix(:,:)
    integer     :: n, i
    type(atoms) :: a
    ! check that the file extension is .pdb
    if(fname2ext(pdbfile) .ne. 'pdb') then
        write(logfhandle, *) 'Wrong extension input file! Should be pdb'
        stop
    endif
    call a%new(pdbfile)
    n = a%get_n()
    allocate(matrix(3,n), source = 0.) ! 3D points
    do i = 1, n
        matrix(:3,i) = a%get_coord(i)
    enddo
    call a%kill
  end subroutine read_pdb2matrix_sp

  ! This subroutine takes in input a pdbfile and saves its
  ! coordinates onto matrix
  subroutine read_pdb2matrix_dp(pdbfile, matrix)
    use simple_fileio, only: fname2ext
    character(len=*),    intent(in)    :: pdbfile
    real(dp),allocatable,intent(inout) :: matrix(:,:)
    integer     :: n, i
    type(atoms) :: a
    ! check that the file extension is .pdb
    if(fname2ext(pdbfile) .ne. 'pdb') then
        write(logfhandle, *) 'Wrong extension input file! Should be pdb'
        stop
    endif
    call a%new(pdbfile)
    n = a%get_n()
    allocate(matrix(3,n), source = 0.d0) ! 3D points
    do i = 1, n
        matrix(:3,i) = real(a%get_coord(i),dp)
    enddo
    call a%kill
  end subroutine read_pdb2matrix_dp

  ! This subroutine takes in input a matrix and saves its
  ! entries onto a pdbfile
  subroutine write_matrix2pdb(matrix, pdbfile)
    use simple_fileio, only: fname2ext
    character(len=*),  intent(in) :: pdbfile
    real,              intent(in) :: matrix(:,:)
    integer     :: n, i
    type(atoms) :: a
    if(size(matrix, dim=1) /= 3) then
        write(logfhandle,*) 'Wrong input matrix dimension!'
        stop
    endif
    n = size(matrix,dim=2)
    call a%new(n, dummy = .true.)
    do i = 1, n
        call a%set_coord(i,matrix(:3,i))
    enddo
    call a%writePDB(pdbfile)
    call a%kill
  end subroutine write_matrix2pdb

  subroutine find_couples_sp(points_P, points_Q, element, P, Q)
      use simple_strings, only: upperCase
      real,             intent(inout) :: points_P(:,:), points_Q(:,:)
      character(len=2), intent(inout) :: element
      real,allocatable, intent(inout) :: P(:,:), Q(:,:) ! just the couples of points
      real    :: theoretical_radius ! for threshold selection
      integer :: n   ! max number of couples
      integer :: cnt ! actual number of couples
      integer :: i, location(1), cnt_P, cnt_Q
      real    :: d
      logical, allocatable :: mask(:)
      real,    allocatable :: points_P_out(:,:), points_Q_out(:,:)
      real,    parameter   :: ABSURD = -10000.
      if(size(points_P) == size(points_Q)) return ! they are already coupled
      ! To modify when we make a module for definitions
      element = upperCase(element)
      select case(element)
          case('PT')
              theoretical_radius = 1.1
              ! thoretical radius is already set
          case('PD')
              theoretical_radius = 1.12
          case('FE')
              theoretical_radius = 1.02
          case('AU')
              theoretical_radius = 1.23
          case default
              write(logfhandle, *)('Unknown atom element; find_couples')
              stop
       end select
       if(size(points_P, dim=2) < size(points_Q, dim=2)) then
         n  = size(points_P, dim=2)
         allocate(mask(n), source = .true.)
         allocate(points_P_out(3,n), points_Q_out(3,n), source = ABSURD) ! init to absurd value
         cnt = 0 ! counts the number of identified couples
         do i = 1, size(points_Q, dim=2)
            d = pixels_dist(points_Q(:,i),points_P(:,:),'min',mask,location,keep_zero=.true.)
            if(d <= 2.*theoretical_radius)then ! has a couple
                cnt = cnt + 1
                points_P_out(:,cnt) = points_P(:,location(1))
                points_Q_out(:,cnt) = points_Q(:,i)
                mask(location(1)) = .false. ! not to consider the same atom more than once
            endif
         enddo
         allocate(P(3,cnt), Q(3,cnt), source = 0.) ! correct size
         print *, 'n: ', n, 'cnt: ', cnt
         cnt_P = 0
         cnt_Q = 0
         do i = 1, n
            if(abs(points_P_out(1,i)-ABSURD) > TINY) then ! check just firts component
                cnt_P = cnt_P + 1
                P(:3,cnt_P) = points_P_out(:3,i)
            endif
            if(abs(points_Q_out(1,i)-ABSURD) > TINY) then
                cnt_Q = cnt_Q + 1
                Q(:3,cnt_Q) = points_Q_out(:3,i)
            endif
         enddo
       else ! size(points_P, dim=2) > size(points_Q, dim=2)
         n  = size(points_Q, dim=2)
         allocate(mask(n), source = .true.)
         allocate(points_P_out(3,n), points_Q_out(3,n), source = ABSURD) ! init to absurd value
         cnt = 0 ! counts the number of identified couples
         do i = 1, size(points_P, dim=2)
            d = pixels_dist(points_P(:,i),points_Q(:,:),'min',mask,location, keep_zero=.true.)
            if(d <= 2.*theoretical_radius)then ! has couple
                cnt = cnt + 1
                points_Q_out(:,cnt) = points_Q(:,location(1))
                points_P_out(:,cnt) = points_P(:,i)
                mask(location(1)) = .false. ! not to consider the same atom more than once
            endif
         enddo
         allocate(P(3,cnt), Q(3,cnt), source = 0.)
         cnt_P = 0
         cnt_Q = 0
         print *, 'n: ', n, 'cnt: ', cnt
         do i = 1, n
            if(abs(points_P_out(1,i)-ABSURD) > TINY) then
                cnt_P = cnt_P + 1
                P(:3,cnt_P) = points_P_out(:3,i)
            endif
            if(abs(points_Q_out(1,i)-ABSURD) > TINY) then
                cnt_Q = cnt_Q + 1
                Q(:3,cnt_Q) = points_Q_out(:3,i)
            endif
         enddo
       endif
       deallocate(mask, points_P_out, points_Q_out)
  end subroutine find_couples_sp

  subroutine find_couples_dp(points_P, points_Q, element, P, Q)
      use simple_strings, only: upperCase
      real(dp),             intent(inout) :: points_P(:,:), points_Q(:,:)
      character(len=2),     intent(inout) :: element
      real(dp),allocatable, intent(inout) :: P(:,:), Q(:,:) ! just the couples of points
      real(dp)    :: theoretical_radius ! for threshold selection
      integer :: n   ! max number of couples
      integer :: cnt ! actual number of couples
      integer :: i, location(1), cnt_P, cnt_Q
      real    :: d
      logical,  allocatable :: mask(:)
      real(dp), allocatable :: points_P_out(:,:), points_Q_out(:,:)
      real(dp), parameter   :: ABSURD = -10000.d0
      if(size(points_P) == size(points_Q)) return ! they are already coupled
      ! To modify when we make a module for definitions
      element = upperCase(element)
      select case(element)
          case('PT')
              theoretical_radius = 1.1d0
              ! thoretical radius is already set
          case('PD')
              theoretical_radius = 1.12d0
          case('FE')
              theoretical_radius = 1.02d0
          case('AU')
              theoretical_radius = 1.23d0
          case default
              write(logfhandle, *)('Unknown atom element; find_couples')
              stop
       end select
       if(size(points_P, dim=2) < size(points_Q, dim=2)) then
         n  = size(points_P, dim=2)
         allocate(mask(n), source = .true.)
         allocate(points_P_out(3,n), points_Q_out(3,n), source = ABSURD) ! init to absurd value
         cnt = 0 ! counts the number of identified couples
         do i = 1, size(points_Q, dim=2)
            d = pixels_dist(real(points_Q(:,i),sp),real(points_P(:,:),sp),'min',mask,location,keep_zero=.true.)
            if(d <= 2.d0*theoretical_radius)then ! has a couple
                cnt = cnt + 1
                points_P_out(:,cnt) = points_P(:,location(1))
                points_Q_out(:,cnt) = points_Q(:,i)
                mask(location(1)) = .false. ! not to consider the same atom more than once
            endif
         enddo
         allocate(P(3,cnt), Q(3,cnt), source = 0.d0) ! correct size
         print *, 'n: ', n, 'cnt: ', cnt
         cnt_P = 0
         cnt_Q = 0
         do i = 1, n
            if(abs(points_P_out(1,i)-ABSURD) > TINY) then ! check just firts component
                cnt_P = cnt_P + 1
                P(:3,cnt_P) = points_P_out(:3,i)
            endif
            if(abs(points_Q_out(1,i)-ABSURD) > TINY) then
                cnt_Q = cnt_Q + 1
                Q(:3,cnt_Q) = points_Q_out(:3,i)
            endif
         enddo
       else ! size(points_P, dim=2) > size(points_Q, dim=2)
         n  = size(points_Q, dim=2)
         allocate(mask(n), source = .true.)
         allocate(points_P_out(3,n), points_Q_out(3,n), source = ABSURD) ! init to absurd value
         cnt = 0 ! counts the number of identified couples
         do i = 1, size(points_P, dim=2)
            d = pixels_dist(real(points_P(:,i),sp),real(points_Q(:,:),sp),'min',mask,location, keep_zero=.true.)
            if(d <= 2.d0*theoretical_radius)then ! has couple
                cnt = cnt + 1
                points_Q_out(:,cnt) = points_Q(:,location(1))
                points_P_out(:,cnt) = points_P(:,i)
                mask(location(1)) = .false. ! not to consider the same atom more than once
            endif
         enddo
         allocate(P(3,cnt), Q(3,cnt), source = 0.d0)
         cnt_P = 0
         cnt_Q = 0
         print *, 'n: ', n, 'cnt: ', cnt
         do i = 1, n
            if(abs(points_P_out(1,i)-ABSURD) > TINY) then
                cnt_P = cnt_P + 1
                P(:3,cnt_P) = points_P_out(:3,i)
            endif
            if(abs(points_Q_out(1,i)-ABSURD) > TINY) then
                cnt_Q = cnt_Q + 1
                Q(:3,cnt_Q) = points_Q_out(:3,i)
            endif
         enddo
       endif
       deallocate(mask, points_P_out, points_Q_out)
  end subroutine find_couples_dp

end module simple_nano_utils
