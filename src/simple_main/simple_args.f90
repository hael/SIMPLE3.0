!==Class simple_args
!
! simple_args is for error checking of the SIMPLE command line arguments. 
! The code is distributed with the hope that it will be useful, but _WITHOUT_ _ANY_ _WARRANTY_. Redistribution 
! or modification is regulated by the GNU General Public License. *Author:* Hans Elmlund, 2011-08-18.
! 
!==Changes are documented below
!
module simple_args
use simple_defs
implicit none

public :: args, test_args
private

integer, parameter :: NARGMAX=500

type args
    private
    character(len=STDLEN) :: args(NARGMAX)
  contains
    procedure :: is_present
end type 

interface args
    module procedure constructor 
end interface

contains

    function constructor( ) result( self )
        type(args) :: self
        self%args(1) = 'acf'
        self%args(2) = 'append'
        self%args(3) = 'async'
        self%args(4) = 'automsk'
        self%args(5) = 'avg'
        self%args(6) = 'bench_gpu'
        self%args(7) = 'bin'
        self%args(8) = 'center'
        self%args(9) = 'clustvalid'
        self%args(10) = 'compare'
        self%args(11) = 'countvox'
        self%args(12) = 'ctfstats'
        self%args(13) = 'cure'
        self%args(14) = 'debug'
        self%args(15) = 'discrete'
        self%args(16) = 'diverse'
        self%args(17) = 'doalign'
        self%args(18) = 'dopca'
        self%args(19) = 'doprint'
        self%args(20) = 'dynlp'
        self%args(21) = 'eo'
        self%args(22) = 'errify'
        self%args(23) = 'even'
        self%args(24) = 'fix_gpu'
        self%args(25) = 'ft2img'
        self%args(26) = 'guinier'
        self%args(27) = 'kmeans'
        self%args(28) = 'local'
        self%args(29) = 'masscen'
        self%args(30) = 'merge'
        self%args(31) = 'mirr'
        self%args(32) = 'neg'
        self%args(33) = 'noise_norm'
        self%args(34) = 'noise'
        self%args(35) = 'norec'
        self%args(36) = 'norm'
        self%args(37) = 'odd'
        self%args(38) = 'order'
        self%args(39) = 'outside'
        self%args(40) = 'pad'
        self%args(41) = 'phaseplate'
        self%args(42) = 'phrand'
        self%args(43) = 'plot'
        self%args(44) = 'readwrite'
        self%args(45) = 'remap'
        self%args(46) = 'restart'
        self%args(47) = 'rnd'
        self%args(48) = 'roalgn'
        self%args(49) = 'round'
        self%args(50) = 'shalgn'
        self%args(51) = 'shellnorm'
        self%args(52) = 'shellw'
        self%args(53) = 'shbarrier'
        self%args(54) = 'single'
        self%args(55) = 'soften'
        self%args(56) = 'srch_inpl'
        self%args(57) = 'stats'
        self%args(58) = 'swap'
        self%args(59) = 'test'
        self%args(60) = 'tomo'
        self%args(61) = 'time'
        self%args(62) = 'trsstats'
        self%args(63) = 'use_gpu'
        self%args(64) = 'verbose'
        self%args(65) = 'vis'
        self%args(66) = 'xfel'
        self%args(67) = 'zero'
        self%args(68) = 'angastunit'
        self%args(69) = 'boxtab'
        self%args(70) = 'boxtype'
        self%args(71) = 'clsdoc'
        self%args(72) = 'comlindoc'
        self%args(73) = 'ctf'
        self%args(74) = 'cwd'
        self%args(75) = 'deftab'
        self%args(76) = 'dfunit'
        self%args(77) = 'dir'
        self%args(78) = 'dir_reject'
        self%args(79) = 'dir_select'
        self%args(80) = 'doclist'
        self%args(81) = 'endian'
        self%args(82) = 'exp_doc'
        self%args(83) = 'ext'
        self%args(84) = 'extrmode'
        self%args(85) = 'fbody'
        self%args(86) = 'featstk'
        self%args(87) = 'filetab'
        self%args(88) = 'fname'
        self%args(89) = 'fsc'
        self%args(90) = 'hfun'
        self%args(91) = 'hist'
        self%args(92) = 'imgkind'
        self%args(93) = 'infile'
        self%args(94) = 'label'
        self%args(95) = 'mskfile'
        self%args(96) = 'msktype'
        self%args(97) = 'opt'
        self%args(98) = 'oritab'
        self%args(99) = 'oritab2'
        self%args(100) = 'outfile'
        self%args(101) = 'outstk'
        self%args(102) = 'outvol'
        self%args(103) = 'paramtab'
        self%args(104) = 'pcastk'
        self%args(105) = 'pdfile'
        self%args(106) = 'pgrp'
        self%args(107) = 'plaintexttab'
        self%args(108) = 'prg'
        self%args(109) = 'refine'
        self%args(110) = 'refs_msk'
        self%args(111) = 'refs'
        self%args(112) = 'speckind'
        self%args(113) = 'split_mode'
        self%args(114) = 'stk_part'
        self%args(115) = 'stk'
        self%args(116) = 'stk2'
        self%args(117) = 'stk3'
        self%args(118) = 'tomoseries'
        self%args(119) = 'vol'
        self%args(120) = 'vollist'
        self%args(121) = 'voltab'
        self%args(122) = 'voltab2'
        self%args(123) = 'wfun'
        self%args(124) = 'astep'
        self%args(125) = 'avgsz'
        self%args(126) = 'binwidth'
        self%args(127) = 'box'
        self%args(128) = 'boxconvsz'
        self%args(129) = 'boxmatch'
        self%args(130) = 'boxpd'
        self%args(131) = 'chunksz'
        self%args(132) = 'class'
        self%args(133) = 'clip'
        self%args(134) = 'corner'
        self%args(135) = 'cube'
        self%args(136) = 'edge'
        self%args(137) = 'find'
        self%args(138) = 'frameavg'
        self%args(139) = 'fromf'
        self%args(140) = 'fromp'
        self%args(141) = 'froms'
        self%args(142) = 'fstep'
        self%args(143) = 'grow'
        self%args(144) = 'iares'
        self%args(145) = 'iptcl'
        self%args(146) = 'jptcl'
        self%args(147) = 'jumpsz'
        self%args(148) = 'maxits'
        self%args(149) = 'maxp'
        self%args(150) = 'minp'
        self%args(151) = 'mrcmode'
        self%args(152) = 'navgs'
        self%args(153) = 'ncunits'
        self%args(154) = 'nbest'
        self%args(155) = 'nboot'
        self%args(156) = 'ncls'
        self%args(157) = 'ncomps'
        self%args(158) = 'ndiscrete'
        self%args(159) = 'ndocs'
        self%args(160) = 'newbox'
        self%args(161) = 'nframes'
        self%args(162) = 'nmembers'
        self%args(163) = 'nnn'
        self%args(164) = 'noris'
        self%args(165) = 'nparts'
        self%args(166) = 'npeaks'
        self%args(167) = 'npix'
        self%args(168) = 'nptcls'
        self%args(169) = 'nran'
        self%args(170) = 'nrefs'
        self%args(171) = 'nrestarts'
        self%args(172) = 'nrots'
        self%args(173) = 'nspace'
        self%args(174) = 'nstates'
        self%args(175) = 'nsym'
        self%args(176) = 'nthr'
        self%args(177) = 'nthr_master'
        self%args(178) = 'numlen'
        self%args(179) = 'nvalid'
        self%args(180) = 'nvars'
        self%args(181) = 'nvox'
        self%args(182) = 'part'
        self%args(183) = 'pcasz'
        self%args(184) = 'ppca'
        self%args(185) = 'pspecsz'
        self%args(186) = 'pspecsz_unblur'
        self%args(187) = 'pspecsz_ctffind'
        self%args(188) = 'ptcl'
        self%args(189) = 'ring1'
        self%args(190) = 'ring2'
        self%args(191) = 'set_gpu'
        self%args(192) = 'spec'
        self%args(193) = 'startit'
        self%args(194) = 'state'
        self%args(195) = 'state2split'
        self%args(196) = 'stepsz'
        self%args(197) = 'tofny'
        self%args(198) = 'tof'
        self%args(199) = 'top'
        self%args(200) = 'tos'
        self%args(201) = 'trsstep'
        self%args(202) = 'update'
        self%args(203) = 'which_iter'
        self%args(204) = 'xdim'
        self%args(205) = 'xdimpd'
        self%args(206) = 'ydim'
        self%args(207) = 'alpha'
        self%args(208) = 'amsklp'
        self%args(209) = 'angerr'
        self%args(210) = 'ares'
        self%args(211) = 'astigerr'
        self%args(212) = 'astigstep'
        self%args(213) = 'athres'
        self%args(214) = 'bfac'
        self%args(215) = 'bfacerr'
        self%args(216) = 'cenlp'
        self%args(217) = 'cs'
        self%args(218) = 'ctfreslim'
        self%args(219) = 'dcrit_rel'
        self%args(220) = 'deflim'
        self%args(221) = 'defocus'
        self%args(222) = 'dens'
        self%args(223) = 'dferr'
        self%args(224) = 'dfmax'
        self%args(225) = 'dfmin'
        self%args(226) = 'dfsdev'
        self%args(227) = 'dose_rate'
        self%args(228) = 'dstep'
        self%args(229) = 'dsteppd'
        self%args(230) = 'e1'
        self%args(231) = 'e2'
        self%args(232) = 'e3'
        self%args(233) = 'eps'
        self%args(234) = 'expastig'
        self%args(235) = 'exp_time'
        self%args(236) = 'filwidth'
        self%args(237) = 'fny'
        self%args(238) = 'frac'
        self%args(239) = 'fraca'
        self%args(240) = 'fracdeadhot'
        self%args(241) = 'fraczero'
        self%args(242) = 'ftol'
        self%args(243) = 'gw'
        self%args(244) = 'hp'
        self%args(245) = 'hp_ctffind'
        self%args(246) = 'inner'
        self%args(247) = 'kv'
        self%args(248) = 'lam'
        self%args(249) = 'lp_dyn'
        self%args(250) = 'lp'
        self%args(251) = 'lp_ctffind'
        self%args(252) = 'lp_pick'
        self%args(253) = 'lpmed'
        self%args(254) = 'lpstart'
        self%args(255) = 'lpstop'
        self%args(256) = 'lpvalid'
        self%args(257) = 'moldiam'
        self%args(258) = 'moment'
        self%args(259) = 'msk'
        self%args(260) = 'mul'
        self%args(261) = 'mw'
        self%args(262) = 'neigh'
        self%args(263) = 'outer'
        self%args(264) = 'phranlp'
        self%args(265) = 'power'
        self%args(266) = 'scale'
        self%args(267) = 'sherr'
        self%args(268) = 'smpd'
        self%args(269) = 'snr'
        self%args(270) = 'thres'
        self%args(271) = 'time_per_image'
        self%args(272) = 'time_per_frame'
        self%args(273) = 'trs'
        self%args(274) = 'var'
        self%args(275) = 'width'
        self%args(276) = 'winsz'
        self%args(277) = 'xsh'
        self%args(278) = 'ysh'
        self%args(279) = 'zsh'
        self%args(280) = 'l_distr_exec'
        self%args(281) = 'doautomsk'
        self%args(282) = 'doshift'
        self%args(283) = 'l_automsk'
        self%args(284) = 'l_dose_weight'
        self%args(285) = 'l_innermsk'
        self%args(286) = 'l_shellw'
        self%args(287) = 'l_xfel'
        self%args(288) = 'vol1'
        self%args(289) = 'vol2'
        self%args(290) = 'vol3'
        self%args(291) = 'vol4'
        self%args(292) = 'vol5'
        self%args(293) = 'vol6'
        self%args(294) = 'vol7'
        self%args(295) = 'vol8'
        self%args(296) = 'vol9'
        self%args(297) = 'vol10'
        self%args(298) = 'vol11'
        self%args(299) = 'vol12'
        self%args(300) = 'vol13'
        self%args(301) = 'vol14'
        self%args(302) = 'vol15'
        self%args(303) = 'vol16'
        self%args(304) = 'vol17'
        self%args(305) = 'vol18'
        self%args(306) = 'vol19'
        self%args(307) = 'vol20'
        self%args(308) = ''
    end function

    function is_present( self, arg ) result( yep )
        class(args), intent(in)      :: self
        character(len=*), intent(in) :: arg
        integer :: i
        logical :: yep
        yep = .false.
        do i=1,NARGMAX
            if( self%args(i) .eq. arg )then
                yep = .true.
                return
            endif
        end do
    end function
    
    subroutine test_args
        use simple_filehandling, only: get_fileunit, nlines
        type(args) :: as
        character(len=STDLEN) :: arg, errarg1, errarg2, errarg3, vlist, spath
        integer :: funit, n, i
        write(*,'(a)') '**info(simple_args_unit_test): testing it all'
        write(*,'(a)') '**info(simple_args_unit_test, part 1): testing for args that should be present'
        as = args()
        funit = get_fileunit()
        spath = '/Users/hael/src/fortran/simple3.0'
        vlist = adjustl(trim(spath))//'/src/simple_main/simple_varlist.txt'
        n = nlines(vlist)
        open(unit=funit, status='old', action='read', file=vlist)
        do i=1,n
            read(funit,*) arg
            if( as%is_present(arg) )then
                ! alles gut
            else
                write(*,'(a)') 'this argument should be present: ', arg 
                stop 'part 1 of the unit test failed' 
            endif 
        end do
        close(funit)
        errarg1 = 'XXXXXXX'
        errarg2 = 'YYYYYY'
        errarg3 = 'ZZZZZZ'
        write(*,'(a)') '**info(simple_args_unit_test, part 2): testing for args that should NOT be present'
        if( as%is_present(errarg1) .or. as%is_present(errarg2) .or. as%is_present(errarg3) )then
            write(*,'(a)') 'the tested argumnets should NOT be present' 
            stop 'part 2 of the unit test failed' 
        endif
        write(*,'(a)') 'SIMPLE_ARGS_UNIT_TEST COMPLETED SUCCESSFULLY ;-)'
    end subroutine

end module simple_args
