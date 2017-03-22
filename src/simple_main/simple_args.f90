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
        self%args(19) = 'dopick'
        self%args(20) = 'doprint'
        self%args(21) = 'dynlp'
        self%args(22) = 'eo'
        self%args(23) = 'errify'
        self%args(24) = 'even'
        self%args(25) = 'fix_gpu'
        self%args(26) = 'ft2img'
        self%args(27) = 'guinier'
        self%args(28) = 'kmeans'
        self%args(29) = 'local'
        self%args(30) = 'masscen'
        self%args(31) = 'merge'
        self%args(32) = 'mirr'
        self%args(33) = 'neg'
        self%args(34) = 'noise_norm'
        self%args(35) = 'noise'
        self%args(36) = 'norec'
        self%args(37) = 'norm'
        self%args(38) = 'odd'
        self%args(39) = 'order'
        self%args(40) = 'outside'
        self%args(41) = 'pad'
        self%args(42) = 'phaseplate'
        self%args(43) = 'phrand'
        self%args(44) = 'plot'
        self%args(45) = 'readwrite'
        self%args(46) = 'remap'
        self%args(47) = 'restart'
        self%args(48) = 'rnd'
        self%args(49) = 'rm_outliers'
        self%args(50) = 'roalgn'
        self%args(51) = 'round'
        self%args(52) = 'shalgn'
        self%args(53) = 'shellnorm'
        self%args(54) = 'shellw'
        self%args(55) = 'shbarrier'
        self%args(56) = 'single'
        self%args(57) = 'soften'
        self%args(58) = 'srch_inpl'
        self%args(59) = 'stats'
        self%args(60) = 'stream'
        self%args(61) = 'swap'
        self%args(62) = 'test'
        self%args(63) = 'tomo'
        self%args(64) = 'time'
        self%args(65) = 'trsstats'
        self%args(66) = 'tseries'
        self%args(67) = 'use_gpu'
        self%args(68) = 'verbose'
        self%args(69) = 'vis'
        self%args(70) = 'xfel'
        self%args(71) = 'zero'
        self%args(72) = 'angastunit'
        self%args(73) = 'boxfile'
        self%args(74) = 'boxtab'
        self%args(75) = 'boxtype'
        self%args(76) = 'clsdoc'
        self%args(77) = 'comlindoc'
        self%args(78) = 'ctf'
        self%args(79) = 'cwd'
        self%args(80) = 'deftab'
        self%args(81) = 'dfunit'
        self%args(82) = 'dir'
        self%args(83) = 'dir_movies'
        self%args(84) = 'dir_reject'
        self%args(85) = 'dir_select'
        self%args(86) = 'dir_target'
        self%args(87) = 'dir_ptcls'
        self%args(88) = 'doclist'
        self%args(89) = 'endian'
        self%args(90) = 'exp_doc'
        self%args(91) = 'ext'
        self%args(92) = 'extrmode'
        self%args(93) = 'fbody'
        self%args(94) = 'featstk'
        self%args(95) = 'filetab'
        self%args(96) = 'fname'
        self%args(97) = 'fsc'
        self%args(98) = 'hfun'
        self%args(99) = 'hist'
        self%args(100) = 'imgkind'
        self%args(101) = 'infile'
        self%args(102) = 'label'
        self%args(103) = 'mskfile'
        self%args(104) = 'msktype'
        self%args(105) = 'opt'
        self%args(106) = 'oritab'
        self%args(107) = 'oritab2'
        self%args(108) = 'outfile'
        self%args(109) = 'outstk'
        self%args(110) = 'outvol'
        self%args(111) = 'ctffind_doc'
        self%args(112) = 'pcastk'
        self%args(113) = 'pdfile'
        self%args(114) = 'pgrp'
        self%args(115) = 'plaintexttab'
        self%args(116) = 'prg'
        self%args(117) = 'refine'
        self%args(118) = 'refs_msk'
        self%args(119) = 'refs'
        self%args(120) = 'speckind'
        self%args(121) = 'split_mode'
        self%args(122) = 'stk_part'
        self%args(123) = 'stk'
        self%args(124) = 'stk2'
        self%args(125) = 'stk3'
        self%args(126) = 'tomoseries'
        self%args(127) = 'vol'
        self%args(128) = 'vollist'
        self%args(129) = 'voltab'
        self%args(130) = 'voltab2'
        self%args(131) = 'wfun'
        self%args(132) = 'astep'
        self%args(133) = 'avgsz'
        self%args(134) = 'binwidth'
        self%args(135) = 'box'
        self%args(136) = 'boxconvsz'
        self%args(137) = 'boxmatch'
        self%args(138) = 'boxpd'
        self%args(139) = 'chunksz'
        self%args(140) = 'class'
        self%args(141) = 'clip'
        self%args(142) = 'corner'
        self%args(143) = 'cube'
        self%args(144) = 'edge'
        self%args(145) = 'find'
        self%args(146) = 'frameavg'
        self%args(147) = 'fromf'
        self%args(148) = 'fromp'
        self%args(149) = 'froms'
        self%args(150) = 'fstep'
        self%args(151) = 'grow'
        self%args(152) = 'iares'
        self%args(153) = 'ind'
        self%args(154) = 'iptcl'
        self%args(155) = 'jptcl'
        self%args(156) = 'jumpsz'
        self%args(157) = 'maxits'
        self%args(158) = 'maxp'
        self%args(159) = 'minp'
        self%args(160) = 'mrcmode'
        self%args(161) = 'navgs'
        self%args(162) = 'ncunits'
        self%args(163) = 'nbest'
        self%args(164) = 'nboot'
        self%args(165) = 'ncls'
        self%args(166) = 'ncomps'
        self%args(167) = 'ndiscrete'
        self%args(168) = 'ndocs'
        self%args(169) = 'newbox'
        self%args(170) = 'nframes'
        self%args(171) = 'nmembers'
        self%args(172) = 'nnn'
        self%args(173) = 'noris'
        self%args(174) = 'nparts'
        self%args(175) = 'npeaks'
        self%args(176) = 'npix'
        self%args(177) = 'nptcls'
        self%args(178) = 'nran'
        self%args(179) = 'nrefs'
        self%args(180) = 'nrestarts'
        self%args(181) = 'nrots'
        self%args(182) = 'nspace'
        self%args(183) = 'nstates'
        self%args(184) = 'nsym'
        self%args(185) = 'nthr'
        self%args(186) = 'nthr_master'
        self%args(187) = 'numlen'
        self%args(188) = 'nvalid'
        self%args(189) = 'nvars'
        self%args(190) = 'nvox'
        self%args(191) = 'offset'
        self%args(192) = 'part'
        self%args(193) = 'pcasz'
        self%args(194) = 'ppca'
        self%args(195) = 'pspecsz'
        self%args(196) = 'pspecsz_unblur'
        self%args(197) = 'pspecsz_ctffind'
        self%args(198) = 'ptcl'
        self%args(199) = 'ring1'
        self%args(200) = 'ring2'
        self%args(201) = 'set_gpu'
        self%args(202) = 'spec'
        self%args(203) = 'startit'
        self%args(204) = 'state'
        self%args(205) = 'state2split'
        self%args(206) = 'stepsz'
        self%args(207) = 'tofny'
        self%args(208) = 'tof'
        self%args(209) = 'top'
        self%args(210) = 'tos'
        self%args(211) = 'trsstep'
        self%args(212) = 'update'
        self%args(213) = 'which_iter'
        self%args(214) = 'xcoord'
        self%args(215) = 'ycoord'
        self%args(216) = 'xdim'
        self%args(217) = 'xdimpd'
        self%args(218) = 'ydim'
        self%args(219) = 'alpha'
        self%args(220) = 'amsklp'
        self%args(221) = 'angerr'
        self%args(222) = 'ares'
        self%args(223) = 'astigerr'
        self%args(224) = 'astigstep'
        self%args(225) = 'athres'
        self%args(226) = 'bfac'
        self%args(227) = 'bfacerr'
        self%args(228) = 'cenlp'
        self%args(229) = 'cs'
        self%args(230) = 'ctfreslim'
        self%args(231) = 'dcrit_rel'
        self%args(232) = 'deflim'
        self%args(233) = 'defocus'
        self%args(234) = 'dens'
        self%args(235) = 'dferr'
        self%args(236) = 'dfmax'
        self%args(237) = 'dfmin'
        self%args(238) = 'dfsdev'
        self%args(239) = 'dose_rate'
        self%args(240) = 'dstep'
        self%args(241) = 'dsteppd'
        self%args(242) = 'e1'
        self%args(243) = 'e2'
        self%args(244) = 'e3'
        self%args(245) = 'eps'
        self%args(246) = 'expastig'
        self%args(247) = 'exp_time'
        self%args(248) = 'filwidth'
        self%args(249) = 'fny'
        self%args(250) = 'frac'
        self%args(251) = 'fraca'
        self%args(252) = 'fracdeadhot'
        self%args(253) = 'fraczero'
        self%args(254) = 'ftol'
        self%args(255) = 'gw'
        self%args(256) = 'het_thresh'
        self%args(257) = 'hp'
        self%args(258) = 'hp_ctffind'
        self%args(259) = 'inner'
        self%args(260) = 'kv'
        self%args(261) = 'lam'
        self%args(262) = 'lp_dyn'
        self%args(263) = 'lp'
        self%args(264) = 'lp_ctffind'
        self%args(265) = 'lp_pick'
        self%args(266) = 'lpmed'
        self%args(267) = 'lpstart'
        self%args(268) = 'lpstop'
        self%args(269) = 'lpvalid'
        self%args(270) = 'moldiam'
        self%args(271) = 'moment'
        self%args(272) = 'msk'
        self%args(273) = 'mul'
        self%args(274) = 'mw'
        self%args(275) = 'neigh'
        self%args(276) = 'outer'
        self%args(277) = 'phranlp'
        self%args(278) = 'power'
        self%args(279) = 'rrate'
        self%args(280) = 'scale'
        self%args(281) = 'sherr'
        self%args(282) = 'smpd'
        self%args(283) = 'snr'
        self%args(284) = 'thres'
        self%args(285) = 'time_per_image'
        self%args(286) = 'time_per_frame'
        self%args(287) = 'trs'
        self%args(288) = 'var'
        self%args(289) = 'width'
        self%args(290) = 'winsz'
        self%args(291) = 'xsh'
        self%args(292) = 'ysh'
        self%args(293) = 'zsh'
        self%args(294) = 'l_distr_exec'
        self%args(295) = 'doautomsk'
        self%args(296) = 'doshift'
        self%args(297) = 'l_automsk'
        self%args(298) = 'l_dose_weight'
        self%args(299) = 'l_innermsk'
        self%args(300) = 'l_pick'
        self%args(301) = 'l_shellw'
        self%args(302) = 'l_xfel'
        self%args(303) = 'vol1'
        self%args(304) = 'vol2'
        self%args(305) = 'vol3'
        self%args(306) = 'vol4'
        self%args(307) = 'vol5'
        self%args(308) = 'vol6'
        self%args(309) = 'vol7'
        self%args(310) = 'vol8'
        self%args(311) = 'vol9'
        self%args(312) = 'vol10'
        self%args(313) = 'vol11'
        self%args(314) = 'vol12'
        self%args(315) = 'vol13'
        self%args(316) = 'vol14'
        self%args(317) = 'vol15'
        self%args(318) = 'vol16'
        self%args(319) = 'vol17'
        self%args(320) = 'vol18'
        self%args(321) = 'vol19'
        self%args(322) = 'vol20'
        self%args(323) = ''
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
