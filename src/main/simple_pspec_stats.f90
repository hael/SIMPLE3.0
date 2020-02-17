!USAGE : simple_exec prg=pspec_stats smpd=1.41 filetab='sjhskl.mrc'
module simple_pspec_stats
include 'simple_lib.f08'
use simple_image,      only: image
use simple_binimage,   only: binimage
use simple_cmdline,    only: cmdline
use simple_parameters, only: parameters
implicit none

public :: pspec_stats
private
#include "simple_local_flags.inc"

logical, parameter :: DEBUG_HERE = .true.
integer, parameter :: BOX        = 512       ! ps size
real,    parameter :: LOW_LIM    = 20.       ! 30 A, lower limit for resolution. Before that, we discard
real,    parameter :: UP_LIM     = 8.        ! 8  A, upper limit for resolution in the entropy calculation. (it was 3. before)
integer, parameter :: N_BINS     = 64        ! number of bins for hist
real,    parameter :: LAMBDA     = 1.        ! for tv filtering
integer, parameter :: N_BIG_CCS  = 5         ! top N_BIG_CCS considered in the avg curvature calculation
real,    parameter :: THR_SCORE_UP_UP = 1.3   ! threshold for keeping/discarding mic wrt score
real,    parameter :: THR_SCORE_UP    = 0.4   ! threshold for keeping/discarding mic wrt score
real,    parameter :: THR_SCORE_DOWN  = 0.25  ! threshold for keeping/discarding mic wrt score
real,    parameter :: THR_CURVAT_UPUP = 6.    ! threshold for keeping/discarding mic wrt average curvature
real,    parameter :: THR_CURVAT_UP   = 4.1   ! threshold for keeping/discarding mic wrt average curvature
real,    parameter :: THR_CURVAT_DOWN = 2.6   ! threshold for keeping/discarding mic wrt average curvature

type :: pspec_stats
    private
    character(len=STDLEN) :: micname  = ''
    character(len=STDLEN) :: fbody    = ''
    type(image)           :: mic            ! micrograph
    type(image)           :: ps             ! power spectrum
    type(binimage)        :: ps_bin, ps_ccs ! its binary version, its connected components
    type(parameters)      :: p
    type(cmdline)         :: cline
    integer :: ldim_mic(3) = 0              ! dim of the mic
    integer :: ldim(3)     = 0              ! dim of the ps`
    real    :: smpd                         ! smpd
    real    :: score       = 0.             ! score, to keep/discard the mic
    real    :: avg_curvat  = 0.
    logical :: fallacious  = .false.        ! whether the mic has to be discarded or not
    integer :: LLim_Findex = 0              ! Fourier index corresponding to LOW_LIM
    integer :: ULim_Findex = 0              ! Fourier index corresponding to UP_LIM
contains
    procedure          :: new => new_pspec_stats
    procedure, private :: empty
    procedure, private :: calc_weighted_avg_sz_ccs   !score
    procedure, private :: calc_avg_curvature         !curvature
    procedure, private :: process_ps
    procedure, private :: print_info
    procedure          :: get_output
    procedure          :: run
    procedure          :: kill => kill_pspec_stats
end type pspec_stats

contains

    subroutine new_pspec_stats(self, name, cline_smpd)
        use simple_defs
        class(pspec_stats), intent(inout) :: self
        character(len=*),        intent(in)    :: name
        real,                    intent(in)    :: cline_smpd
        integer     :: nptcls
        real        :: smpd
        type(image) :: hist_stretch  !to perform histogram stretching (see Adiga s paper)
        !set parameters
        self%smpd        = cline_smpd
        self%micname     = name
        self%ULim_Findex = calc_fourier_index(max(2.*self%smpd,UP_LIM), BOX,self%smpd)! Everything at a resolution higher than UP_LIM A is discarded
        self%LLim_Findex = calc_fourier_index(LOW_LIM,BOX,self%smpd)                  ! Everything at a resolution lower than LOW_LIM A is discarded
        call find_ldim_nptcls(self%micname, self%ldim_mic, nptcls, smpd)
        self%fbody   = get_fbody(trim(self%micname),trim(fname2ext(self%micname)))
        call self%mic%new(self%ldim_mic, self%smpd)
        call self%mic%read(self%micname)
        self%ldim(1) = BOX
        self%ldim(2) = BOX
        self%ldim(3) = 1
        call self%ps_bin%new_bimg(self%ldim, self%smpd)
        call self%ps_ccs%new_bimg(self%ldim, self%smpd)
        !power spectrum generation
        call self%mic%mic2spec(BOX, 'sqrt',LOW_LIM, self%ps)
        if(DEBUG_HERE) call self%ps%write(PATH_HERE//basename(trim(self%fbody))//'_generated_ps.mrc')
    end subroutine new_pspec_stats

    ! Result of the combination of score and curvature.
    ! It states whether to keep or discard the mic.
    ! Notation: L <-> low;
    !           M <-> medium;
    !           H <-> high;
    !           S <-> score;
    !           C <-> curvature.
    ! H.S        --> keep
    ! H.C        --> discard
    ! L.S + L.C  --> keep
    ! L.S + M.C  --> discard
    ! M.S + M.C  --> discard
    ! M.S + L.C  --> keep
    function get_output(self) result(keep_mic)
        class(pspec_stats), intent(inout) :: self
        logical :: keep_mic
        ! print *,'THR_SCORE_UP', THR_SCORE_UP
        ! print *,'THR_SCORE_DOWN', THR_SCORE_DOWN
        ! print *,'THR_CURVAT_UPUP', THR_CURVAT_UPUP
        ! print *,'THR_CURVAT_UP', THR_CURVAT_UP
        ! print *,'THR_CURVAT_DOWN', THR_CURVAT_DOWN
        if(DEBUG_HERE) write(logfhandle,*) 'score = ',self%score, 'avg_curvat = ', self%avg_curvat
        if(self%score > THR_SCORE_UP_UP) then
            keep_mic = .true.
            print *, 'keep because score very high'
            return
        elseif(self%score >= THR_SCORE_UP .and. self%score < THR_SCORE_UP_UP) then
            if(self%avg_curvat > THR_CURVAT_UPUP) then
                keep_mic = .false.
                print *, 'discard: score high but curvature also high'
                return
            else
                keep_mic = .true.
                print *, 'keep: high score and curvature not high'
                return
            endif
        elseif(self%score >= THR_SCORE_DOWN .and. self%score < THR_SCORE_UP) then
            if(self%avg_curvat > THR_CURVAT_UP) then
                keep_mic = .false.
                print *, 'discard: low score but curvature not so low'
                return
            else
                keep_mic = .true.
                print *, 'keep:  low score and low curvature'
                return
            endif
        elseif(self%score < THR_SCORE_DOWN) then
            if(self%avg_curvat > THR_CURVAT_DOWN) then
                keep_mic = .false.
                print *, 'discard: low score'
                return
            else
                keep_mic = .true.
                print *, 'keep:  low score and low curvature'
                return
            endif
        else
            keep_mic = .false.
            THROW_WARN('This case has not been considered')
        endif
    end function get_output

    !This subroutine is meant to discard fallacious power spectra images
    !characterized by producing an 'empty' binarization.
    !If after binarization the # of white pixels detected in the central
    !zone of the image is less than 5% of the tot
    !# of central pixels, than it returns yes, otherwhise no.
    !The central zone is characterized by having res in [LOW_LIM,UP_LIM/2]
    function empty(self) result(yes_no)
        class(pspec_stats), intent(inout) :: self
        logical             :: yes_no
        real, allocatable   :: rmat(:,:,:)
        real, parameter     :: PERCENT = 0.05
        integer :: i, j
        integer :: h, k, sh
        integer :: cnt, cnt_white
        integer :: uplim
        uplim = self%ULim_Findex/2
        yes_no = .false.
        rmat = self%ps_bin%get_rmat()
        if(any(rmat > 1.001) .or. any(rmat < -0.001)) THROW_HARD('Expected binary image in input; discard_ps')
        !initialize
        cnt       = 0
        cnt_white = 0
        do i = 1, BOX
            do j = 1, BOX
                h   = -int(BOX/2) + i - 1
                k   = -int(BOX/2) + j - 1
                sh  =  nint(hyp(real(h),real(k)))
                if(sh < uplim .and. sh > self%LLim_Findex) then
                    cnt = cnt + 1                                !number of pixels in the selected zone
                    if(rmat(i,j,1) > TINY) cnt_white = cnt_white + 1 !number of white pixels in the selected zone
                endif
             enddo
        enddo
        if(real(cnt_white)/real(cnt)<PERCENT) yes_no = .true.; return
        deallocate(rmat)
    end function empty

    subroutine print_info(self)
        class(pspec_stats), intent(inout) :: self
        character(len = 100) :: iom
        integer              :: status
        open(unit = 17, access = 'sequential', action = 'readwrite',file = basename(trim(self%fbody))//"PowerSpectraAnalysis.txt", form = 'formatted', iomsg = iom, iostat = status, position = 'append', status = 'replace')
        write(unit = 17, fmt = '(a)') '>>>>>>>>>>>>>>>>>>>>POWER SPECTRA STATISTICS>>>>>>>>>>>>>>>>>>'
        write(unit = 17, fmt = '(a)') ''
        write(unit = 17, fmt = "(a,a)")  'Input mic  ', basename(trim(self%fbody))
        write(unit = 17, fmt = "(a,i0,tr1,i0,tr1,i0)") 'Logical dim mic ', self%mic%get_ldim()
        write(unit = 17, fmt = "(a,i0,tr1,i0,tr1,i0)") 'Logical dim ps  ', self%ps%get_ldim()
        write(unit = 17, fmt = "(a,f0.2)")             'Smpd            ', self%smpd
        write(unit = 17, fmt = '(a)') ''
        write(unit = 17, fmt = "(a)")  '-----------SELECTED PARAMETERS------------- '
        write(unit = 17, fmt = '(a)') ''
        write(unit = 17, fmt = "(a,f5.2,a,f5.2, a)") 'Pixel split up in shells in the interval', 2.*self%smpd, ' - ', LOW_LIM,' A'
    end subroutine print_info

   ! This subroutine calculates the weighted avg of the size
   ! of the connected components of the binary version of
   ! the power spectrum. The aim is to discard fallacious
   ! micrographs based on the analysis of their power
   ! spectra. The valid ones should have rings in the
   ! center, so big connected components toward the
   ! center of the image.
   ! This is the SCORE.
    subroutine calc_weighted_avg_sz_ccs(self, sz)
        class(pspec_stats), intent(inout) :: self
        integer, allocatable :: imat(:,:,:), imat_sz(:,:,:), sz(:)
        integer :: h,k,sh
        integer :: i, j
        real    :: denom  !denominator of the formula
        real    :: a
        denom = 0.
        ! call self%ps_ccs%write(PATH_HERE//basename(trim(self%fbody))//'BeforeElimCCs.mrc')
        ! STILL TO DO?
        call self%ps_ccs%elim_ccs([4,BOX*4]) !eliminate connected components with size one
        ! call self%ps_ccs%write(PATH_HERE//basename(trim(self%fbody))//'AfterElimCCs.mrc')
        imat = nint(self%ps_ccs%get_rmat())
        allocate(imat_sz(BOX,BOX,1), source = 0)
        sz = self%ps_ccs%size_ccs()
        call generate_mat_sz_ccs(imat,imat_sz,sz)
        self%score = 0.  !initialise
        do i = 2, BOX-1  !discard border effects due to binarization
            do j = 2, BOX-1
                if(imat(i,j,1) > 0) then
                    h   = -int(BOX/2) + i - 1
                    k   = -int(BOX/2) + j - 1
                    sh  =  nint(hyp(real(h),real(k)))
                    a = (1.-real(sh)/real(self%ULim_Findex))
                    denom = denom + a
                    self%score = self%score + a*imat_sz(i,j,1)/(2.*PI*sh)
                else
                    call self%ps_bin%set([i,j,1], 0.)
                endif
            enddo
        enddo
        call self%ps_bin%write(PATH_HERE//basename(trim(self%fbody))//'_binarized_polished.mrc') !if(DEBUG_HERE)
        call self%ps_bin%find_ccs(self%ps_ccs, update_imat = .true.)
        self%avg_curvat = self%calc_avg_curvature()
        !normalization
        if(abs(denom) > TINY) then
            self%score = self%score/denom
        else
            THROW_HARD('Denominator = 0! calc_weighted_avg_sz_ccs')
        endif
    contains

        ! This subroutine is meant to generate a matrix in which in each pixel is
        ! stored the size of the correspondent connected component. Moreover
        ! the ccs outside the rage [LOW_LIM,UP_LIM] are COMPLETELY removed (otherwise
        ! the size of the ccs would be incorrect).
        subroutine generate_mat_sz_ccs(imat_in,imat_out,sz)
            integer, intent(inout)  :: imat_in (:,:,:)
            integer, intent(out)    :: imat_out(:,:,:)
            integer, intent(inout)  :: sz(:)
            integer :: i, j, k, h, sh
            if(size(imat_in) .ne. size(imat_out)) THROW_HARD('Input and Output matrices have to have the same dim!')
            do i = 2, BOX-1  !discard border effects due to binarization
                do j = 2, BOX-1
                    if(imat_in(i,j,1) > 0 .and. imat_out(i,j,1) == 0) then ! condition on imat_out is not to set it more than once
                        h   = -int(BOX/2) + i - 1
                        k   = -int(BOX/2) + j - 1
                        sh  =  nint(hyp(real(h),real(k)))
                        if( sh > self%ULim_Findex .or. sh < self%LLim_Findex ) then
                            sz(imat_in(i,j,1)) = 0
                            where(imat_in == imat_in(i,j,1)) imat_in = 0 ! set to 0 ALL the cc
                        else
                            where(imat_in == imat_in(i,j,1)) imat_out = sz(imat_in(i,j,1))
                        endif
                    endif
                enddo
            enddo
        end subroutine generate_mat_sz_ccs
    end subroutine calc_weighted_avg_sz_ccs

    ! This function calculates the average curvature of the
    ! top N_BIG_CCS (in size) connected components.
    function calc_avg_curvature(self) result(avg)
        use simple_binimage, only: binimage
        class(pspec_stats), intent(inout) :: self
        real    :: avg !average curvature
        integer :: i
        integer :: cc(1)
        integer, allocatable :: sz(:)
        sz = self%ps_ccs%size_ccs()
        avg = 0.
        do i = 1,N_BIG_CCS
            cc(:) = maxloc(sz)
            avg = avg + estimate_curvature(self%ps_ccs,cc(1))
            sz(cc(1)) = 0 !discard
        enddo
        avg = avg/N_BIG_CCS
    contains
        ! This subroutine estimates the curvature of the connected
        ! component cc in the connected component image of the ps.
        ! The curvature is defined as the ratio between the nb
        ! of pixels in the cc and the ideal circumference arc which
        ! has the same extremes as cc.
        function estimate_curvature(ps_ccs,cc) result(c)
            type(binimage), intent(inout) :: ps_ccs
            integer,        intent(in)    :: cc ! number of the connected component to estimate the curvature
            real        :: c                    ! estimation of the curvature of the cc img
            type(image) :: img_aux
            integer, allocatable :: imat_cc(:,:,:), imat_aux(:,:,:)
            integer, allocatable :: pos(:,:)
            integer :: xmax, xmin, ymax, ymin
            integer :: i, j
            integer :: h, k, sh
            integer :: sz, nb_pxls
            logical :: done ! to prematurely exit the loops
            call img_aux%new(self%ldim, self%smpd)
            imat_cc = nint(ps_ccs%get_rmat())
            where(imat_cc /= cc) imat_cc = 0 ! keep just the considered cc
            allocate(imat_aux(BOX,BOX,1), source = 0)
            ! fetch white pixel positions
            call get_pixel_pos(imat_cc,pos)
            done = .false.
            do i = 1,BOX
                do j = 1,BOX
                    if(imat_cc(i,j,1) > 0) then      !The first white pixel you meet, consider it
                      h   = -int(BOX/2) + i - 1
                      k   = -int(BOX/2) + j - 1
                      sh  =  nint(hyp(real(h),real(k))) !Identify the shell the px belongs to: radius of the ideal circle
                      ! Count the nb of white pixels in a circle of radius sh, TO OPTIMISE
                      call circumference(img_aux,real(sh))
                      ! Image of the ideal circle of radius sh compared to the input data
                      imat_aux = nint(img_aux%get_rmat())
                      ! Need to move from ellipse --> arc. Identify extreme points of the arc
                      xmin = minval(pos(1,:))
                      xmin = min(i,xmin)
                      xmax = maxval(pos(1,:))
                      xmax = max(i,xmax)
                      ymin = minval(pos(2,:))
                      ymin = min(j,ymin)
                      ymax = maxval(pos(2,:))
                      ymax = max(j,ymax)
                      ! Check if the cc is a segment
                      if(ymin == ymax .or. xmin == xmax) then
                          print *, 'This cc is a segment, curvature is 0'
                           c = 0.
                           return
                      endif
                      ! Set to zero white pxls that are not in the arc
                      imat_aux(1:xmin-2,:,1) = 0 !-2 for tickness
                      imat_aux(:,1:ymin-2,1) = 0
                      imat_aux(xmax+2:BOX,:,1) = 0
                      imat_aux(:,ymax+2:BOX,1) = 0
                      nb_pxls = count(imat_aux > 0)  !nb of white pxls in the ideal arc
                      sz = count(imat_cc > 0) !number of white pixels in the cc
                      c = real(sz)/(nb_pxls)
                      return
                  endif
              enddo
          enddo
        end function estimate_curvature

        !Circumference of radius r and center the center of the img.
        !Gray value of the new build circumference 1.
        subroutine circumference(img, rad)
            type(image), intent(inout) :: img
            real,        intent(in)    :: rad
            integer :: i, j, sh, h, k
            do i = 1, BOX
                do j = 1, BOX
                    h   = -int(BOX/2) + i - 1
                    k   = -int(BOX/2) + j - 1
                    sh  =  nint(hyp(real(h),real(k)))
                    if(abs(real(sh)-rad)<1) call img%set([i,j,1], 1.)
                  enddo
              enddo
        end subroutine circumference
    end function calc_avg_curvature

    !This is the core subroutine of this module. Preprocessing and binarization of the
    !ps is performed here. Then estimation of how far do the detected rings extend.
    ! Finally estimation of the number of countiguous rings.
    subroutine process_ps(self)
      class(pspec_stats), intent(inout) :: self
      integer, allocatable :: sz(:)
      real                 :: res
      integer              :: ind(1)
      integer              :: h, k, sh
      integer              :: i, j
      call prepare_ps(self)
      call binarize_ps(self)
      ! calculation of the weighted average size of the ccs ->  score
      call self%ps_bin%find_ccs(self%ps_ccs)
      sz = self%ps_ccs%size_ccs()
      call self%calc_weighted_avg_sz_ccs(sz)
      deallocate(sz)
  contains

      !Preprocessing steps: -) tv filtering
      !                     -) elimination of central spot
      !                     -) scaling
      subroutine prepare_ps(self)
          use simple_tvfilter, only: tvfilter
          class(pspec_stats), intent(inout) :: self
          type(tvfilter) :: tvf
          call tvf%new()
          call tvf%apply_filter(self%ps, LAMBDA)
          call manage_central_spot(self)
          call self%ps%scale_pixels([1.,real(N_BINS)])
      end subroutine prepare_ps

      ! This subroutine extract a circle from the central part of the
      ! power spectrum, until LOW_LIM A and replace these gray values with
      ! the weighted average of the gray values in the ps outside that circle.
      ! The weight is the dist from the center. It's done to make it
      ! smoother.
      ! It is meant to reduce the influence of the central pixel.
      subroutine manage_central_spot(self)
          class(pspec_stats), intent(inout) :: self
          real, allocatable :: rmat(:,:,:), rmat_dist(:,:,:)
          real              :: avg
          integer           :: lims(3,2), mh, mk
          integer           :: i, j
          integer           :: k, h, sh
          integer           :: cnt
          logical           :: lmsk(BOX,BOX,1)
          lmsk = .true.
          allocate(rmat     (BOX,BOX,1), source = self%ps%get_rmat())
          allocate(rmat_dist(BOX,BOX,1), source = 0.)
          lims = self%ps%loop_lims(3)
          mh   = abs(lims(1,1))
          mk   = abs(lims(2,1))
          avg  = 0. !initialisations
          cnt  = 0
          do h=lims(1,1),lims(1,2)
              do k=lims(2,1),lims(2,2)
                  sh  = nint(hyp(real(h),real(k))) !shell to which px
                  i = min(max(1,h+mh+1),BOX)
                  j = min(max(1,k+mk+1),BOX)
                  if(sh < self%LLim_Findex ) then
                      lmsk(i,j,1) = .false.
                  elseif(sh >= self%LLim_Findex .and. sh < self%LLim_Findex + 2) then
                      avg = avg + rmat(i,j,1)
                      cnt = cnt + 1
                  endif
              enddo
          enddo
          avg = avg / real(cnt)
          do h=lims(1,1),lims(1,2)
              do k=lims(2,1),lims(2,2)
                  sh  = nint(hyp(real(h),real(k))) !shell to which px
                  i = min(max(1,h+mh+1),BOX)
                  j = min(max(1,k+mk+1),BOX)
                  if(sh < self%LLim_Findex ) then
                      rmat_dist(i,j,1) = sqrt(real((i-BOX/2-1)**2+(j-BOX/2-1)**2)) !dist between [i,j,1] and [BOX/2,BOX/2,1] (distance from the center)
                  endif
              enddo
          enddo
          rmat_dist = rmat_dist/maxval(rmat_dist)
          where( .not.lmsk ) rmat = avg*rmat_dist
          call self%ps%set_rmat(rmat)
      end subroutine manage_central_spot

      ! This subroutine performs binarization of a ps image
      ! using Canny edge detection with automatic threshold
      ! selection.
      subroutine binarize_ps(self)
          use simple_segmentation, only : canny
          class(pspec_stats), intent(inout) :: self
          real,    allocatable :: rmat_bin(:,:,:)
          integer     :: ldim(3),i
          real        :: scale_range(2)
          scale_range = [1.,real(BOX)]
          call canny(self%ps,self%ps_bin)
          ! call canny(self%ps,self%ps_bin,scale_range = scale_range) !MODIFIED 30/09/19
          do i=1,BOX  !get rid of border effects
              call self%ps_bin%set([i,1,1],0.)
              call self%ps_bin%set([i,BOX,1],0.)
              call self%ps_bin%set([1,i,1],0.)
              call self%ps_bin%set([BOX,i,1],0.)
          enddo
          if(DEBUG_HERE) call self%ps_bin%write(PATH_HERE//basename(trim(self%fbody))//'_binarized.mrc')
          self%fallacious =  self%empty() !check if the mic is fallacious
          if(self%fallacious) write(logfhandle,*) basename(trim(self%fbody)), ' TO BE DISCARDED'
      end subroutine binarize_ps
  end subroutine process_ps

  subroutine run(self)
      class(pspec_stats), intent(inout) :: self
      call self%p%new(self%cline)
      write(logfhandle,*) '******> Processing PS ',basename(trim(self%fbody))
      call process_ps(self)
  end subroutine run

  subroutine kill_pspec_stats(self)
      class(pspec_stats), intent(inout) :: self
      call self%mic%kill()
      call self%ps%kill()
      call self%ps_bin%kill()
      call self%ps_ccs%kill()
      self%micname      = ''
      self%fbody        = ''
      self%ldim         = 0
      self%smpd         = 0.
      self%score        = 0.
      self%avg_curvat   = 0.
      self%fallacious   = .false.
  end subroutine kill_pspec_stats
end module simple_pspec_stats

! SUBROUTINES MIGHT BE USEFUL
! subroutine log_ps(self,img_out)
!     class(pspec_stats), intent(inout) :: self
!     type(image), optional :: img_out
!     real, allocatable :: rmat(:,:,:)
!     ! call self%ps%scale_pixels([1.,real(BOX)*2.+1.]) !not to have problems in calculating the log
!     rmat = self%ps%get_rmat()
!     rmat = log(rmat)
!     if(present(img_out)) then
!         call img_out%new(self%ldim, self%smpd)
!         call img_out%set_rmat(rmat)
!     else
!         call self%ps%set_rmat(rmat)
!     endif
!     deallocate(rmat)
! end subroutine log_ps
