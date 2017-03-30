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
        self%args(46) = 'restart'
        self%args(47) = 'rnd'
        self%args(48) = 'rm_outliers'
        self%args(49) = 'roalgn'
        self%args(50) = 'round'
        self%args(51) = 'shalgn'
        self%args(52) = 'shellnorm'
        self%args(53) = 'shellw'
        self%args(54) = 'shbarrier'
        self%args(55) = 'single'
        self%args(56) = 'soften'
        self%args(57) = 'srch_inpl'
        self%args(58) = 'stats'
        self%args(59) = 'stream'
        self%args(60) = 'swap'
        self%args(61) = 'test'
        self%args(62) = 'tomo'
        self%args(63) = 'time'
        self%args(64) = 'trsstats'
        self%args(65) = 'tseries'
        self%args(66) = 'use_gpu'
        self%args(67) = 'verbose'
        self%args(68) = 'vis'
        self%args(69) = 'xfel'
        self%args(70) = 'zero'
        self%args(71) = 'angastunit'
        self%args(72) = 'boxfile'
        self%args(73) = 'boxtab'
        self%args(74) = 'boxtype'
        self%args(75) = 'clsdoc'
        self%args(76) = 'comlindoc'
        self%args(77) = 'ctf'
        self%args(78) = 'cwd'
        self%args(79) = 'deftab'
        self%args(80) = 'dfunit'
        self%args(81) = 'dir'
        self%args(82) = 'dir_movies'
        self%args(83) = 'dir_reject'
        self%args(84) = 'dir_select'
        self%args(85) = 'dir_target'
        self%args(86) = 'dir_ptcls'
        self%args(87) = 'doclist'
        self%args(88) = 'endian'
        self%args(89) = 'exp_doc'
        self%args(90) = 'ext'
        self%args(91) = 'extrmode'
        self%args(92) = 'fbody'
        self%args(93) = 'featstk'
        self%args(94) = 'filetab'
        self%args(95) = 'fname'
        self%args(96) = 'fsc'
        self%args(97) = 'hfun'
        self%args(98) = 'hist'
        self%args(99) = 'imgkind'
        self%args(100) = 'infile'
        self%args(101) = 'label'
        self%args(102) = 'mskfile'
        self%args(103) = 'msktype'
        self%args(104) = 'opt'
        self%args(105) = 'oritab'
        self%args(106) = 'oritab2'
        self%args(107) = 'outfile'
        self%args(108) = 'outstk'
        self%args(109) = 'outstk2'
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
        self%args(134) = 'batchsz'
        self%args(135) = 'binwidth'
        self%args(136) = 'box'
        self%args(137) = 'boxconvsz'
        self%args(138) = 'boxmatch'
        self%args(139) = 'boxpd'
        self%args(140) = 'chunksz'
        self%args(141) = 'class'
        self%args(142) = 'clip'
        self%args(143) = 'corner'
        self%args(144) = 'cube'
        self%args(145) = 'edge'
        self%args(146) = 'filtsz_pad'
        self%args(147) = 'find'
        self%args(148) = 'frameavg'
        self%args(149) = 'fromf'
        self%args(150) = 'fromp'
        self%args(151) = 'froms'
        self%args(152) = 'fstep'
        self%args(153) = 'grow'
        self%args(154) = 'iares'
        self%args(155) = 'ind'
        self%args(156) = 'iptcl'
        self%args(157) = 'jptcl'
        self%args(158) = 'jumpsz'
        self%args(159) = 'maxits'
        self%args(160) = 'maxp'
        self%args(161) = 'minp'
        self%args(162) = 'mrcmode'
        self%args(163) = 'navgs'
        self%args(164) = 'ncunits'
        self%args(165) = 'nbest'
        self%args(166) = 'nboot'
        self%args(167) = 'ncls'
        self%args(168) = 'ncomps'
        self%args(169) = 'ndiscrete'
        self%args(170) = 'ndocs'
        self%args(171) = 'newbox'
        self%args(172) = 'newbox2'
        self%args(173) = 'nframes'
        self%args(174) = 'nmembers'
        self%args(175) = 'nnn'
        self%args(176) = 'noris'
        self%args(177) = 'nparts'
        self%args(178) = 'npeaks'
        self%args(179) = 'npix'
        self%args(180) = 'nptcls'
        self%args(181) = 'nran'
        self%args(182) = 'nrefs'
        self%args(183) = 'nrestarts'
        self%args(184) = 'nrots'
        self%args(185) = 'nspace'
        self%args(186) = 'nstates'
        self%args(187) = 'nsym'
        self%args(188) = 'nthr'
        self%args(189) = 'nthr_master'
        self%args(190) = 'numlen'
        self%args(191) = 'nvalid'
        self%args(192) = 'nvars'
        self%args(193) = 'nvox'
        self%args(194) = 'offset'
        self%args(195) = 'part'
        self%args(196) = 'pcasz'
        self%args(197) = 'ppca'
        self%args(198) = 'pspecsz'
        self%args(199) = 'pspecsz_unblur'
        self%args(200) = 'pspecsz_ctffind'
        self%args(201) = 'ptcl'
        self%args(202) = 'ring1'
        self%args(203) = 'ring2'
        self%args(204) = 'set_gpu'
        self%args(205) = 'spec'
        self%args(206) = 'startit'
        self%args(207) = 'state'
        self%args(208) = 'state2split'
        self%args(209) = 'stepsz'
        self%args(210) = 'tofny'
        self%args(211) = 'tof'
        self%args(212) = 'top'
        self%args(213) = 'tos'
        self%args(214) = 'trsstep'
        self%args(215) = 'update'
        self%args(216) = 'which_iter'
        self%args(217) = 'xcoord'
        self%args(218) = 'ycoord'
        self%args(219) = 'xdim'
        self%args(220) = 'xdimpd'
        self%args(221) = 'ydim'
        self%args(222) = 'alpha'
        self%args(223) = 'amsklp'
        self%args(224) = 'angerr'
        self%args(225) = 'ares'
        self%args(226) = 'astigerr'
        self%args(227) = 'astigstep'
        self%args(228) = 'athres'
        self%args(229) = 'batchfrac'
        self%args(230) = 'bfac'
        self%args(231) = 'bfacerr'
        self%args(232) = 'cenlp'
        self%args(233) = 'cs'
        self%args(234) = 'ctfreslim'
        self%args(235) = 'dcrit_rel'
        self%args(236) = 'deflim'
        self%args(237) = 'defocus'
        self%args(238) = 'dens'
        self%args(239) = 'dferr'
        self%args(240) = 'dfmax'
        self%args(241) = 'dfmin'
        self%args(242) = 'dfsdev'
        self%args(243) = 'dose_rate'
        self%args(244) = 'dstep'
        self%args(245) = 'dsteppd'
        self%args(246) = 'e1'
        self%args(247) = 'e2'
        self%args(248) = 'e3'
        self%args(249) = 'eps'
        self%args(250) = 'extr_thresh'
        self%args(251) = 'expastig'
        self%args(252) = 'exp_time'
        self%args(253) = 'filwidth'
        self%args(254) = 'fny'
        self%args(255) = 'frac'
        self%args(256) = 'fraca'
        self%args(257) = 'fracdeadhot'
        self%args(258) = 'fraczero'
        self%args(259) = 'ftol'
        self%args(260) = 'gw'
        self%args(261) = 'het_thresh'
        self%args(262) = 'hp'
        self%args(263) = 'hp_ctffind'
        self%args(264) = 'inner'
        self%args(265) = 'kv'
        self%args(266) = 'lam'
        self%args(267) = 'lp_dyn'
        self%args(268) = 'lp'
        self%args(269) = 'lp_ctffind'
        self%args(270) = 'lp_pick'
        self%args(271) = 'lpmed'
        self%args(272) = 'lpstart'
        self%args(273) = 'lpstop'
        self%args(274) = 'lpvalid'
        self%args(275) = 'moldiam'
        self%args(276) = 'moment'
        self%args(277) = 'msk'
        self%args(278) = 'mul'
        self%args(279) = 'mw'
        self%args(280) = 'neigh'
        self%args(281) = 'outer'
        self%args(282) = 'phranlp'
        self%args(283) = 'power'
        self%args(284) = 'rrate'
        self%args(285) = 'scale'
        self%args(286) = 'scale2'
        self%args(287) = 'sherr'
        self%args(288) = 'smpd'
        self%args(289) = 'snr'
        self%args(290) = 'thres'
        self%args(291) = 'time_per_image'
        self%args(292) = 'time_per_frame'
        self%args(293) = 'trs'
        self%args(294) = 'var'
        self%args(295) = 'width'
        self%args(296) = 'winsz'
        self%args(297) = 'xsh'
        self%args(298) = 'ysh'
        self%args(299) = 'zsh'
        self%args(300) = 'l_distr_exec'
        self%args(301) = 'doautomsk'
        self%args(302) = 'doshift'
        self%args(303) = 'l_automsk'
        self%args(304) = 'l_dose_weight'
        self%args(305) = 'l_innermsk'
        self%args(306) = 'l_pick'
        self%args(307) = 'l_shellw'
        self%args(308) = 'l_xfel'
        self%args(309) = 'vol1'
        self%args(310) = 'vol2'
        self%args(311) = 'vol3'
        self%args(312) = 'vol4'
        self%args(313) = 'vol5'
        self%args(314) = 'vol6'
        self%args(315) = 'vol7'
        self%args(316) = 'vol8'
        self%args(317) = 'vol9'
        self%args(318) = 'vol10'
        self%args(319) = 'vol11'
        self%args(320) = 'vol12'
        self%args(321) = 'vol13'
        self%args(322) = 'vol14'
        self%args(323) = 'vol15'
        self%args(324) = 'vol16'
        self%args(325) = 'vol17'
        self%args(326) = 'vol18'
        self%args(327) = 'vol19'
        self%args(328) = 'vol20'
        self%args(329) = ''
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
