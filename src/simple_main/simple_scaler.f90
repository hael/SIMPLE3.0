!> Simple module for scaling images or stacks
module simple_scaler
use simple_cmdline, only: cmdline
use simple_defs     ! use all in there
implicit none

public :: scaler
private

type :: scaler
    private
    type(cmdline)         :: cline_scale
    character(len=STDLEN) :: native_stk, stk_sc
    real                  :: native_smpd, native_msk, smpd_sc, scale, msk_sc
    integer               :: native_box, box_sc, nptcls
  contains
    ! init/uninit
    procedure :: init
    procedure :: uninit
    ! exec
    procedure :: scale_exec
    ! getters
    procedure :: update_smpd_msk
    procedure :: update_stk_smpd_msk
    procedure :: get_scaled_var
    procedure :: get_native_var
end type scaler

contains

    subroutine init( self, p_master, cline, smpd_target, stkscaledbody )
        use simple_magic_boxes, only: autoscale
        use simple_params,      only: params
        class(scaler)    :: self
        class(params)    :: p_master
        class(cmdline)   :: cline
        real             :: smpd_target
        character(len=*) :: stkscaledbody
        self%native_stk  = p_master%stk
        self%native_smpd = p_master%smpd
        self%native_msk  = p_master%msk
        self%native_box  = p_master%box
        self%nptcls      = p_master%nptcls
        self%cline_scale = cline
        call autoscale(p_master%box, p_master%smpd,&
        &smpd_target, self%box_sc, self%smpd_sc, self%scale)
        self%msk_sc = self%scale * p_master%msk
        self%stk_sc = trim(stkscaledbody)//p_master%ext
        call self%cline_scale%set('newbox', real(self%box_sc))
        call self%cline_scale%set('outstk', trim(self%stk_sc))
        call cline%set('stk',  trim(self%stk_sc))
        call cline%set('smpd', self%smpd_sc)
        call cline%set('msk',  self%msk_sc)
    end subroutine init

    subroutine uninit( self, cline )
        class(scaler)  :: self
        class(cmdline) :: cline
        call cline%set('stk',  trim(self%native_stk))
        call cline%set('smpd', self%native_smpd)
        call cline%set('msk',  self%native_msk)        
    end subroutine uninit

    subroutine scale_exec( self )
        use simple_commander_imgproc, only: scale_commander
        use simple_jiffys,            only: has_ldim_nptcls
        use simple_filehandling,      only: file_exists
        class(scaler)         :: self
        type(scale_commander) :: xscale
        logical :: doscale
        if( file_exists(trim(self%stk_sc)) )then
            if( has_ldim_nptcls(self%stk_sc, [self%box_sc,self%box_sc,1], self%nptcls) )then
                doscale = .false.
            else
                doscale = .true.
            endif
        else
            doscale = .true.
        endif
        if( doscale )then
            write(*,'(A)') '>>>'
            write(*,'(A)') '>>> AUTO-SCALING IMAGES'
            write(*,'(A)') '>>>'
            call xscale%execute(self%cline_scale)
        endif
    end subroutine scale_exec

    subroutine update_smpd_msk( self, cline, which )
        class(scaler)    :: self
        class(cmdline)   :: cline
        character(len=*) :: which
        select case(which)
            case('scaled')
                call cline%set('smpd', self%smpd_sc)
                call cline%set('msk',  self%msk_sc)
            case('native')
                call cline%set('smpd', self%native_smpd)
                call cline%set('msk',  self%native_msk)
            case DEFAULT
                 write(*,*) 'flag ', trim(which), ' is unsupported'
                stop 'simple_scaler :: update_smpd_msk'
        end select
    end subroutine update_smpd_msk

    subroutine update_stk_smpd_msk( self, cline, which )
        class(scaler)    :: self
        class(cmdline)   :: cline
        character(len=*) :: which
        select case(which)
            case('scaled')
                call cline%set('stk',  self%stk_sc)
                call cline%set('smpd', self%smpd_sc)
                call cline%set('msk',  self%msk_sc)
            case('native')
                call cline%set('stk',  self%native_stk)
                call cline%set('smpd', self%native_smpd)
                call cline%set('msk',  self%native_msk)
            case DEFAULT
                 write(*,*) 'flag ', trim(which), ' is unsupported'
                stop 'simple_scaler :: update_stk_smpd_msk'
        end select
    end subroutine update_stk_smpd_msk

    real function get_scaled_var( self, which )
        class(scaler)    :: self
        character(len=*) :: which
        select case(which)
            case('smpd')
                get_scaled_var = self%smpd_sc
            case('scale')
                get_scaled_var = self%scale
            case('msk')
                get_scaled_var = self%msk_sc
            case('box')
                get_scaled_var = real(self%box_sc)
            case DEFAULT
                write(*,*) 'flag ', trim(which), ' is unsupported'
                stop 'simple_scaler :: get_scaled_var'
        end select
    end function get_scaled_var

    real function get_native_var( self, which )
        class(scaler)    :: self
        character(len=*) :: which
        select case(which)
            case('smpd')
                get_native_var = self%native_smpd
            case('msk')
                get_native_var = self%native_msk
            case('box')
                get_native_var = real(self%native_box)
            case DEFAULT
                write(*,*) 'flag ', trim(which), ' is unsupported'
                stop 'simple_scaler :: get_native_var'
        end select
    end function get_native_var

end module simple_scaler
