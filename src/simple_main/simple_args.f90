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
        self%args(5) = 'autoscale'
        self%args(6) = 'avg'
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
        self%args(41) = 'pgrp_known'
        self%args(42) = 'phaseplate'
        self%args(43) = 'phrand'
        self%args(44) = 'plot'
        self%args(45) = 'readwrite'
        self%args(46) = 'remap_classes'
        self%args(47) = 'restart'
        self%args(48) = 'rnd'
        self%args(49) = 'rm_outliers'
        self%args(50) = 'roalgn'
        self%args(51) = 'round'
        self%args(52) = 'shalgn'
        self%args(53) = 'shellnorm'
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
        self%args(66) = 'verbose'
        self%args(67) = 'vis'
        self%args(68) = 'xfel'
        self%args(69) = 'zero'
        self%args(70) = 'angastunit'
        self%args(71) = 'boxfile'
        self%args(72) = 'boxtab'
        self%args(73) = 'boxtype'
        self%args(74) = 'chunktag'
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
        self%args(89) = 'exec_abspath'
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
        self%args(122) = 'speckind'
        self%args(123) = 'split_mode'
        self%args(124) = 'stk_part'
        self%args(125) = 'stk_part_fbody'
        self%args(126) = 'stk'
        self%args(127) = 'stk2'
        self%args(128) = 'stk3'
        self%args(129) = 'tomoseries'
        self%args(130) = 'unidoc'
        self%args(131) = 'vol'
        self%args(132) = 'vollist'
        self%args(133) = 'voltab'
        self%args(134) = 'voltab2'
        self%args(135) = 'wfun'
        self%args(136) = 'astep'
        self%args(137) = 'avgsz'
        self%args(138) = 'batchsz'
        self%args(139) = 'binwidth'
        self%args(140) = 'box'
        self%args(141) = 'boxconvsz'
        self%args(142) = 'boxmatch'
        self%args(143) = 'boxpd'
        self%args(144) = 'chunk'
        self%args(145) = 'chunksz'
        self%args(146) = 'class'
        self%args(147) = 'clip'
        self%args(148) = 'corner'
        self%args(149) = 'cube'
        self%args(150) = 'edge'
        self%args(151) = 'find'
        self%args(152) = 'nframesgrp'
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
        self%args(163) = 'kstop_grid'
        self%args(164) = 'maxits'
        self%args(165) = 'maxp'
        self%args(166) = 'minp'
        self%args(167) = 'mrcmode'
        self%args(168) = 'navgs'
        self%args(169) = 'ncunits'
        self%args(170) = 'nbest'
        self%args(171) = 'nboot'
        self%args(172) = 'ncls'
        self%args(173) = 'ncomps'
        self%args(174) = 'ndiscrete'
        self%args(175) = 'ndocs'
        self%args(176) = 'newbox'
        self%args(177) = 'newbox2'
        self%args(178) = 'nframes'
        self%args(179) = 'nmembers'
        self%args(180) = 'nnn'
        self%args(181) = 'noris'
        self%args(182) = 'nparts'
        self%args(183) = 'npeaks'
        self%args(184) = 'npix'
        self%args(185) = 'nptcls'
        self%args(186) = 'nran'
        self%args(187) = 'nrefs'
        self%args(188) = 'nrestarts'
        self%args(189) = 'nrots'
        self%args(190) = 'nspace'
        self%args(191) = 'nstates'
        self%args(192) = 'nsub'
        self%args(193) = 'nsym'
        self%args(194) = 'nthr'
        self%args(195) = 'nthr_master'
        self%args(196) = 'numlen'
        self%args(197) = 'nvalid'
        self%args(198) = 'nvars'
        self%args(199) = 'nvox'
        self%args(200) = 'offset'
        self%args(201) = 'part'
        self%args(202) = 'pcasz'
        self%args(203) = 'ppca'
        self%args(204) = 'pspecsz'
        self%args(205) = 'pspecsz_unblur'
        self%args(206) = 'pspecsz_ctffind'
        self%args(207) = 'ptcl'
        self%args(208) = 'ring1'
        self%args(209) = 'ring2'
        self%args(210) = 'spec'
        self%args(211) = 'startit'
        self%args(212) = 'state'
        self%args(213) = 'state2split'
        self%args(214) = 'stepsz'
        self%args(215) = 'szsn'
        self%args(216) = 'tofny'
        self%args(217) = 'tof'
        self%args(218) = 'top'
        self%args(219) = 'tos'
        self%args(220) = 'trsstep'
        self%args(221) = 'update'
        self%args(222) = 'which_iter'
        self%args(223) = 'xcoord'
        self%args(224) = 'ycoord'
        self%args(225) = 'xdim'
        self%args(226) = 'xdimpd'
        self%args(227) = 'ydim'
        self%args(228) = 'alpha'
        self%args(229) = 'amsklp'
        self%args(230) = 'angerr'
        self%args(231) = 'ares'
        self%args(232) = 'astigerr'
        self%args(233) = 'astigstep'
        self%args(234) = 'athres'
        self%args(235) = 'batchfrac'
        self%args(236) = 'bfac'
        self%args(237) = 'bfacerr'
        self%args(238) = 'cenlp'
        self%args(239) = 'cs'
        self%args(240) = 'ctfreslim'
        self%args(241) = 'dcrit_rel'
        self%args(242) = 'deflim'
        self%args(243) = 'defocus'
        self%args(244) = 'dens'
        self%args(245) = 'dferr'
        self%args(246) = 'dfmax'
        self%args(247) = 'dfmin'
        self%args(248) = 'dfsdev'
        self%args(249) = 'dose_rate'
        self%args(250) = 'dstep'
        self%args(251) = 'dsteppd'
        self%args(252) = 'e1'
        self%args(253) = 'e2'
        self%args(254) = 'e3'
        self%args(255) = 'eps'
        self%args(256) = 'extr_thresh'
        self%args(257) = 'expastig'
        self%args(258) = 'exp_time'
        self%args(259) = 'filwidth'
        self%args(260) = 'fny'
        self%args(261) = 'frac'
        self%args(262) = 'fraca'
        self%args(263) = 'fracdeadhot'
        self%args(264) = 'fraczero'
        self%args(265) = 'ftol'
        self%args(266) = 'gw'
        self%args(267) = 'hp'
        self%args(268) = 'hp_ctffind'
        self%args(269) = 'inner'
        self%args(270) = 'kv'
        self%args(271) = 'lam'
        self%args(272) = 'lp_dyn'
        self%args(273) = 'lp_grid'
        self%args(274) = 'lp'
        self%args(275) = 'lp_ctffind'
        self%args(276) = 'lp_pick'
        self%args(277) = 'lpmed'
        self%args(278) = 'lpstart'
        self%args(279) = 'lpstop'
        self%args(280) = 'lpvalid'
        self%args(281) = 'moldiam'
        self%args(282) = 'moment'
        self%args(283) = 'msk'
        self%args(284) = 'mul'
        self%args(285) = 'mw'
        self%args(286) = 'neigh'
        self%args(287) = 'nsig'
        self%args(288) = 'outer'
        self%args(289) = 'phranlp'
        self%args(290) = 'power'
        self%args(291) = 'rrate'
        self%args(292) = 'scale'
        self%args(293) = 'scale2'
        self%args(294) = 'sherr'
        self%args(295) = 'smpd'
        self%args(296) = 'snr'
        self%args(297) = 'thres'
        self%args(298) = 'time_per_image'
        self%args(299) = 'time_per_frame'
        self%args(300) = 'trs'
        self%args(301) = 'var'
        self%args(302) = 'width'
        self%args(303) = 'winsz'
        self%args(304) = 'xsh'
        self%args(305) = 'ysh'
        self%args(306) = 'zsh'
        self%args(307) = 'l_distr_exec'
        self%args(308) = 'l_chunk_distr'
        self%args(309) = 'doautomsk'
        self%args(310) = 'doshift'
        self%args(311) = 'l_automsk'
        self%args(312) = 'l_autoscale'
        self%args(313) = 'l_dose_weight'
        self%args(314) = 'l_innermsk'
        self%args(315) = 'l_pick'
        self%args(316) = 'l_remap_classes'
        self%args(317) = 'l_xfel'
        self%args(318) = 'vol1'
        self%args(319) = 'vol2'
        self%args(320) = 'vol3'
        self%args(321) = 'vol4'
        self%args(322) = 'vol5'
        self%args(323) = 'vol6'
        self%args(324) = 'vol7'
        self%args(325) = 'vol8'
        self%args(326) = 'vol9'
        self%args(327) = 'vol10'
        self%args(328) = 'vol11'
        self%args(329) = 'vol12'
        self%args(330) = 'vol13'
        self%args(331) = 'vol14'
        self%args(332) = 'vol15'
        self%args(333) = 'vol16'
        self%args(334) = 'vol17'
        self%args(335) = 'vol18'
        self%args(336) = 'vol19'
        self%args(337) = 'vol20'
        self%args(338) = ''
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
        spath = '/home/hael/src/simple3.0'
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
