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
        self%args(75) = 'chunktag'
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
        self%args(108) = 'oritab3D'
        self%args(109) = 'outfile'
        self%args(110) = 'outstk'
        self%args(111) = 'outstk2'
        self%args(112) = 'outvol'
        self%args(113) = 'ctffind_doc'
        self%args(114) = 'pcastk'
        self%args(115) = 'pdfile'
        self%args(116) = 'pgrp'
        self%args(117) = 'plaintexttab'
        self%args(118) = 'prg'
        self%args(119) = 'refine'
        self%args(120) = 'refs_msk'
        self%args(121) = 'refs'
        self%args(122) = 'shellwfile'
        self%args(123) = 'speckind'
        self%args(124) = 'split_mode'
        self%args(125) = 'stk_part'
        self%args(126) = 'stk'
        self%args(127) = 'stk2'
        self%args(128) = 'stk3'
        self%args(129) = 'tomoseries'
        self%args(130) = 'vol'
        self%args(131) = 'vollist'
        self%args(132) = 'voltab'
        self%args(133) = 'voltab2'
        self%args(134) = 'wfun'
        self%args(135) = 'astep'
        self%args(136) = 'avgsz'
        self%args(137) = 'batchsz'
        self%args(138) = 'binwidth'
        self%args(139) = 'box'
        self%args(140) = 'boxconvsz'
        self%args(141) = 'boxmatch'
        self%args(142) = 'boxpd'
        self%args(143) = 'chunk'
        self%args(144) = 'chunksz'
        self%args(145) = 'class'
        self%args(146) = 'clip'
        self%args(147) = 'corner'
        self%args(148) = 'cube'
        self%args(149) = 'edge'
        self%args(150) = 'filtsz_pad'
        self%args(151) = 'find'
        self%args(152) = 'frameavg'
        self%args(153) = 'fromf'
        self%args(154) = 'fromp'
        self%args(155) = 'froms'
        self%args(156) = 'fstep'
        self%args(157) = 'grow'
        self%args(158) = 'iares'
        self%args(159) = 'ind'
        self%args(160) = 'iptcl'
        self%args(161) = 'jptcl'
        self%args(162) = 'jumpsz'
        self%args(163) = 'maxits'
        self%args(164) = 'maxp'
        self%args(165) = 'minp'
        self%args(166) = 'mrcmode'
        self%args(167) = 'navgs'
        self%args(168) = 'ncunits'
        self%args(169) = 'nbest'
        self%args(170) = 'nboot'
        self%args(171) = 'ncls'
        self%args(172) = 'ncomps'
        self%args(173) = 'ndiscrete'
        self%args(174) = 'ndocs'
        self%args(175) = 'newbox'
        self%args(176) = 'newbox2'
        self%args(177) = 'nframes'
        self%args(178) = 'nmembers'
        self%args(179) = 'nnn'
        self%args(180) = 'noris'
        self%args(181) = 'nparts'
        self%args(182) = 'npeaks'
        self%args(183) = 'npix'
        self%args(184) = 'nptcls'
        self%args(185) = 'nran'
        self%args(186) = 'nrefs'
        self%args(187) = 'nrestarts'
        self%args(188) = 'nrots'
        self%args(189) = 'nspace'
        self%args(190) = 'nstates'
        self%args(191) = 'nsym'
        self%args(192) = 'nthr'
        self%args(193) = 'nthr_master'
        self%args(194) = 'numlen'
        self%args(195) = 'nvalid'
        self%args(196) = 'nvars'
        self%args(197) = 'nvox'
        self%args(198) = 'offset'
        self%args(199) = 'part'
        self%args(200) = 'pcasz'
        self%args(201) = 'ppca'
        self%args(202) = 'pspecsz'
        self%args(203) = 'pspecsz_unblur'
        self%args(204) = 'pspecsz_ctffind'
        self%args(205) = 'ptcl'
        self%args(206) = 'ring1'
        self%args(207) = 'ring2'
        self%args(208) = 'set_gpu'
        self%args(209) = 'spec'
        self%args(210) = 'startit'
        self%args(211) = 'state'
        self%args(212) = 'state2split'
        self%args(213) = 'stepsz'
        self%args(214) = 'tofny'
        self%args(215) = 'tof'
        self%args(216) = 'top'
        self%args(217) = 'tos'
        self%args(218) = 'trsstep'
        self%args(219) = 'update'
        self%args(220) = 'which_iter'
        self%args(221) = 'xcoord'
        self%args(222) = 'ycoord'
        self%args(223) = 'xdim'
        self%args(224) = 'xdimpd'
        self%args(225) = 'ydim'
        self%args(226) = 'alpha'
        self%args(227) = 'amsklp'
        self%args(228) = 'angerr'
        self%args(229) = 'ares'
        self%args(230) = 'astigerr'
        self%args(231) = 'astigstep'
        self%args(232) = 'athres'
        self%args(233) = 'batchfrac'
        self%args(234) = 'bfac'
        self%args(235) = 'bfacerr'
        self%args(236) = 'cenlp'
        self%args(237) = 'cs'
        self%args(238) = 'ctfreslim'
        self%args(239) = 'dcrit_rel'
        self%args(240) = 'deflim'
        self%args(241) = 'defocus'
        self%args(242) = 'dens'
        self%args(243) = 'dferr'
        self%args(244) = 'dfmax'
        self%args(245) = 'dfmin'
        self%args(246) = 'dfsdev'
        self%args(247) = 'dose_rate'
        self%args(248) = 'dstep'
        self%args(249) = 'dsteppd'
        self%args(250) = 'e1'
        self%args(251) = 'e2'
        self%args(252) = 'e3'
        self%args(253) = 'eps'
        self%args(254) = 'extr_thresh'
        self%args(255) = 'expastig'
        self%args(256) = 'exp_time'
        self%args(257) = 'filwidth'
        self%args(258) = 'fny'
        self%args(259) = 'frac'
        self%args(260) = 'fraca'
        self%args(261) = 'fracdeadhot'
        self%args(262) = 'fraczero'
        self%args(263) = 'ftol'
        self%args(264) = 'gw'
        self%args(265) = 'het_thresh'
        self%args(266) = 'hp'
        self%args(267) = 'hp_ctffind'
        self%args(268) = 'inner'
        self%args(269) = 'kv'
        self%args(270) = 'lam'
        self%args(271) = 'lp_dyn'
        self%args(272) = 'lp'
        self%args(273) = 'lp_ctffind'
        self%args(274) = 'lp_pick'
        self%args(275) = 'lpmed'
        self%args(276) = 'lpstart'
        self%args(277) = 'lpstop'
        self%args(278) = 'lpvalid'
        self%args(279) = 'moldiam'
        self%args(280) = 'moment'
        self%args(281) = 'msk'
        self%args(282) = 'mul'
        self%args(283) = 'mw'
        self%args(284) = 'neigh'
        self%args(285) = 'nsig'
        self%args(286) = 'outer'
        self%args(287) = 'phranlp'
        self%args(288) = 'power'
        self%args(289) = 'rrate'
        self%args(290) = 'scale'
        self%args(291) = 'scale2'
        self%args(292) = 'sherr'
        self%args(293) = 'smpd'
        self%args(294) = 'snr'
        self%args(295) = 'thres'
        self%args(296) = 'time_per_image'
        self%args(297) = 'time_per_frame'
        self%args(298) = 'trs'
        self%args(299) = 'var'
        self%args(300) = 'width'
        self%args(301) = 'winsz'
        self%args(302) = 'xsh'
        self%args(303) = 'ysh'
        self%args(304) = 'zsh'
        self%args(305) = 'l_distr_exec'
        self%args(306) = 'l_chunk_distr'
        self%args(307) = 'doautomsk'
        self%args(308) = 'doshift'
        self%args(309) = 'l_automsk'
        self%args(310) = 'l_dose_weight'
        self%args(311) = 'l_innermsk'
        self%args(312) = 'l_pick'
        self%args(313) = 'l_shellw'
        self%args(314) = 'l_xfel'
        self%args(315) = 'vol1'
        self%args(316) = 'vol2'
        self%args(317) = 'vol3'
        self%args(318) = 'vol4'
        self%args(319) = 'vol5'
        self%args(320) = 'vol6'
        self%args(321) = 'vol7'
        self%args(322) = 'vol8'
        self%args(323) = 'vol9'
        self%args(324) = 'vol10'
        self%args(325) = 'vol11'
        self%args(326) = 'vol12'
        self%args(327) = 'vol13'
        self%args(328) = 'vol14'
        self%args(329) = 'vol15'
        self%args(330) = 'vol16'
        self%args(331) = 'vol17'
        self%args(332) = 'vol18'
        self%args(333) = 'vol19'
        self%args(334) = 'vol20'
        self%args(335) = ''
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
