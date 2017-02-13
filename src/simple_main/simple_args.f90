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
        self%args(78) = 'dir_movies'
        self%args(79) = 'dir_reject'
        self%args(80) = 'dir_select'
        self%args(81) = 'dir_target'
        self%args(82) = 'doclist'
        self%args(83) = 'endian'
        self%args(84) = 'exp_doc'
        self%args(85) = 'ext'
        self%args(86) = 'extrmode'
        self%args(87) = 'fbody'
        self%args(88) = 'featstk'
        self%args(89) = 'filetab'
        self%args(90) = 'fname'
        self%args(91) = 'fsc'
        self%args(92) = 'hfun'
        self%args(93) = 'hist'
        self%args(94) = 'imgkind'
        self%args(95) = 'infile'
        self%args(96) = 'label'
        self%args(97) = 'mskfile'
        self%args(98) = 'msktype'
        self%args(99) = 'opt'
        self%args(100) = 'oritab'
        self%args(101) = 'oritab2'
        self%args(102) = 'outfile'
        self%args(103) = 'outstk'
        self%args(104) = 'outvol'
        self%args(105) = 'paramtab'
        self%args(106) = 'pcastk'
        self%args(107) = 'pdfile'
        self%args(108) = 'pgrp'
        self%args(109) = 'plaintexttab'
        self%args(110) = 'prg'
        self%args(111) = 'refine'
        self%args(112) = 'refs_msk'
        self%args(113) = 'refs'
        self%args(114) = 'speckind'
        self%args(115) = 'split_mode'
        self%args(116) = 'stk_part'
        self%args(117) = 'stk'
        self%args(118) = 'stk2'
        self%args(119) = 'stk3'
        self%args(120) = 'tomoseries'
        self%args(121) = 'vol'
        self%args(122) = 'vollist'
        self%args(123) = 'voltab'
        self%args(124) = 'voltab2'
        self%args(125) = 'wfun'
        self%args(126) = 'astep'
        self%args(127) = 'avgsz'
        self%args(128) = 'binwidth'
        self%args(129) = 'box'
        self%args(130) = 'boxconvsz'
        self%args(131) = 'boxmatch'
        self%args(132) = 'boxpd'
        self%args(133) = 'chunksz'
        self%args(134) = 'class'
        self%args(135) = 'clip'
        self%args(136) = 'corner'
        self%args(137) = 'cube'
        self%args(138) = 'edge'
        self%args(139) = 'find'
        self%args(140) = 'frameavg'
        self%args(141) = 'fromf'
        self%args(142) = 'fromp'
        self%args(143) = 'froms'
        self%args(144) = 'fstep'
        self%args(145) = 'grow'
        self%args(146) = 'iares'
        self%args(147) = 'iptcl'
        self%args(148) = 'jptcl'
        self%args(149) = 'jumpsz'
        self%args(150) = 'maxits'
        self%args(151) = 'maxp'
        self%args(152) = 'minp'
        self%args(153) = 'mrcmode'
        self%args(154) = 'navgs'
        self%args(155) = 'ncunits'
        self%args(156) = 'nbest'
        self%args(157) = 'nboot'
        self%args(158) = 'ncls'
        self%args(159) = 'ncomps'
        self%args(160) = 'ndiscrete'
        self%args(161) = 'ndocs'
        self%args(162) = 'newbox'
        self%args(163) = 'nframes'
        self%args(164) = 'nmembers'
        self%args(165) = 'nnn'
        self%args(166) = 'noris'
        self%args(167) = 'nparts'
        self%args(168) = 'npeaks'
        self%args(169) = 'npix'
        self%args(170) = 'nptcls'
        self%args(171) = 'nran'
        self%args(172) = 'nrefs'
        self%args(173) = 'nrestarts'
        self%args(174) = 'nrots'
        self%args(175) = 'nspace'
        self%args(176) = 'nstates'
        self%args(177) = 'nsym'
        self%args(178) = 'nthr'
        self%args(179) = 'nthr_master'
        self%args(180) = 'numlen'
        self%args(181) = 'nvalid'
        self%args(182) = 'nvars'
        self%args(183) = 'nvox'
        self%args(184) = 'part'
        self%args(185) = 'pcasz'
        self%args(186) = 'ppca'
        self%args(187) = 'pspecsz'
        self%args(188) = 'pspecsz_unblur'
        self%args(189) = 'pspecsz_ctffind'
        self%args(190) = 'ptcl'
        self%args(191) = 'ring1'
        self%args(192) = 'ring2'
        self%args(193) = 'set_gpu'
        self%args(194) = 'spec'
        self%args(195) = 'startit'
        self%args(196) = 'state'
        self%args(197) = 'state2split'
        self%args(198) = 'stepsz'
        self%args(199) = 'tofny'
        self%args(200) = 'tof'
        self%args(201) = 'top'
        self%args(202) = 'tos'
        self%args(203) = 'trsstep'
        self%args(204) = 'update'
        self%args(205) = 'which_iter'
        self%args(206) = 'xdim'
        self%args(207) = 'xdimpd'
        self%args(208) = 'ydim'
        self%args(209) = 'alpha'
        self%args(210) = 'amsklp'
        self%args(211) = 'angerr'
        self%args(212) = 'ares'
        self%args(213) = 'astigerr'
        self%args(214) = 'astigstep'
        self%args(215) = 'athres'
        self%args(216) = 'bfac'
        self%args(217) = 'bfacerr'
        self%args(218) = 'cenlp'
        self%args(219) = 'cs'
        self%args(220) = 'ctfreslim'
        self%args(221) = 'dcrit_rel'
        self%args(222) = 'deflim'
        self%args(223) = 'defocus'
        self%args(224) = 'dens'
        self%args(225) = 'dferr'
        self%args(226) = 'dfmax'
        self%args(227) = 'dfmin'
        self%args(228) = 'dfsdev'
        self%args(229) = 'dose_rate'
        self%args(230) = 'dstep'
        self%args(231) = 'dsteppd'
        self%args(232) = 'e1'
        self%args(233) = 'e2'
        self%args(234) = 'e3'
        self%args(235) = 'eps'
        self%args(236) = 'expastig'
        self%args(237) = 'exp_time'
        self%args(238) = 'filwidth'
        self%args(239) = 'fny'
        self%args(240) = 'frac'
        self%args(241) = 'fraca'
        self%args(242) = 'fracdeadhot'
        self%args(243) = 'fraczero'
        self%args(244) = 'ftol'
        self%args(245) = 'gw'
        self%args(246) = 'hp'
        self%args(247) = 'hp_ctffind'
        self%args(248) = 'inner'
        self%args(249) = 'kv'
        self%args(250) = 'lam'
        self%args(251) = 'lp_dyn'
        self%args(252) = 'lp'
        self%args(253) = 'lp_ctffind'
        self%args(254) = 'lp_pick'
        self%args(255) = 'lpmed'
        self%args(256) = 'lpstart'
        self%args(257) = 'lpstop'
        self%args(258) = 'lpvalid'
        self%args(259) = 'moldiam'
        self%args(260) = 'moment'
        self%args(261) = 'msk'
        self%args(262) = 'mul'
        self%args(263) = 'mw'
        self%args(264) = 'neigh'
        self%args(265) = 'outer'
        self%args(266) = 'phranlp'
        self%args(267) = 'power'
        self%args(268) = 'scale'
        self%args(269) = 'sherr'
        self%args(270) = 'smpd'
        self%args(271) = 'snr'
        self%args(272) = 'thres'
        self%args(273) = 'time_per_image'
        self%args(274) = 'time_per_frame'
        self%args(275) = 'trs'
        self%args(276) = 'var'
        self%args(277) = 'width'
        self%args(278) = 'winsz'
        self%args(279) = 'xsh'
        self%args(280) = 'ysh'
        self%args(281) = 'zsh'
        self%args(282) = 'l_distr_exec'
        self%args(283) = 'doautomsk'
        self%args(284) = 'doshift'
        self%args(285) = 'l_automsk'
        self%args(286) = 'l_dose_weight'
        self%args(287) = 'l_innermsk'
        self%args(288) = 'l_shellw'
        self%args(289) = 'l_xfel'
        self%args(290) = 'vol1'
        self%args(291) = 'vol2'
        self%args(292) = 'vol3'
        self%args(293) = 'vol4'
        self%args(294) = 'vol5'
        self%args(295) = 'vol6'
        self%args(296) = 'vol7'
        self%args(297) = 'vol8'
        self%args(298) = 'vol9'
        self%args(299) = 'vol10'
        self%args(300) = 'vol11'
        self%args(301) = 'vol12'
        self%args(302) = 'vol13'
        self%args(303) = 'vol14'
        self%args(304) = 'vol15'
        self%args(305) = 'vol16'
        self%args(306) = 'vol17'
        self%args(307) = 'vol18'
        self%args(308) = 'vol19'
        self%args(309) = 'vol20'
        self%args(310) = ''
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
        spath = '/home/cyril/Simple3'
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
