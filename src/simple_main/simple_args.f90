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
        self%args(4) = 'autoscale'
        self%args(5) = 'avg'
        self%args(6) = 'bin'
        self%args(7) = 'center'
        self%args(8) = 'clustvalid'
        self%args(9) = 'compare'
        self%args(10) = 'countvox'
        self%args(11) = 'ctfstats'
        self%args(12) = 'cure'
        self%args(13) = 'debug'
        self%args(14) = 'discrete'
        self%args(15) = 'diverse'
        self%args(16) = 'doalign'
        self%args(17) = 'dopca'
        self%args(18) = 'dopick'
        self%args(19) = 'doprint'
        self%args(20) = 'dynlp'
        self%args(21) = 'eo'
        self%args(22) = 'errify'
        self%args(23) = 'even'
        self%args(24) = 'ft2img'
        self%args(25) = 'guinier'
        self%args(26) = 'kmeans'
        self%args(27) = 'local'
        self%args(28) = 'masscen'
        self%args(29) = 'merge'
        self%args(30) = 'mirr'
        self%args(31) = 'neg'
        self%args(32) = 'noise_norm'
        self%args(33) = 'noise'
        self%args(34) = 'norec'
        self%args(35) = 'norm'
        self%args(36) = 'odd'
        self%args(37) = 'order'
        self%args(38) = 'outside'
        self%args(39) = 'pad'
        self%args(40) = 'pgrp_known'
        self%args(41) = 'phaseplate'
        self%args(42) = 'phrand'
        self%args(43) = 'plot'
        self%args(44) = 'readwrite'
        self%args(45) = 'remap_classes'
        self%args(46) = 'restart'
        self%args(47) = 'rnd'
        self%args(48) = 'rm_outliers'
        self%args(49) = 'roalgn'
        self%args(50) = 'round'
        self%args(51) = 'shalgn'
        self%args(52) = 'shellnorm'
        self%args(53) = 'shbarrier'
        self%args(54) = 'single'
        self%args(55) = 'soften'
        self%args(56) = 'stats'
        self%args(57) = 'stream'
        self%args(58) = 'swap'
        self%args(59) = 'test'
        self%args(60) = 'tomo'
        self%args(61) = 'time'
        self%args(62) = 'trsstats'
        self%args(63) = 'tseries'
        self%args(64) = 'verbose'
        self%args(65) = 'vis'
        self%args(66) = 'xfel'
        self%args(67) = 'weights2D'
        self%args(68) = 'zero'
        self%args(69) = 'angastunit'
        self%args(70) = 'automsk'
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
        self%args(119) = 'real_filter'
        self%args(120) = 'refine'
        self%args(121) = 'refs_msk'
        self%args(122) = 'refs'
        self%args(123) = 'speckind'
        self%args(124) = 'split_mode'
        self%args(125) = 'stk_part'
        self%args(126) = 'stk_part_fbody'
        self%args(127) = 'stk'
        self%args(128) = 'stk2'
        self%args(129) = 'stk3'
        self%args(130) = 'tomoseries'
        self%args(131) = 'unidoc'
        self%args(132) = 'vol'
        self%args(133) = 'vollist'
        self%args(134) = 'voltab'
        self%args(135) = 'voltab2'
        self%args(136) = 'wfun'
        self%args(137) = 'astep'
        self%args(138) = 'avgsz'
        self%args(139) = 'batchsz'
        self%args(140) = 'binwidth'
        self%args(141) = 'box'
        self%args(142) = 'boxconvsz'
        self%args(143) = 'boxmatch'
        self%args(144) = 'boxpd'
        self%args(145) = 'chunk'
        self%args(146) = 'chunksz'
        self%args(147) = 'class'
        self%args(148) = 'clip'
        self%args(149) = 'corner'
        self%args(150) = 'cube'
        self%args(151) = 'edge'
        self%args(152) = 'find'
        self%args(153) = 'nframesgrp'
        self%args(154) = 'fromf'
        self%args(155) = 'fromp'
        self%args(156) = 'froms'
        self%args(157) = 'fstep'
        self%args(158) = 'grow'
        self%args(159) = 'iares'
        self%args(160) = 'ind'
        self%args(161) = 'iptcl'
        self%args(162) = 'jptcl'
        self%args(163) = 'jumpsz'
        self%args(164) = 'kstop_grid'
        self%args(165) = 'maxits'
        self%args(166) = 'maxp'
        self%args(167) = 'minp'
        self%args(168) = 'mrcmode'
        self%args(169) = 'navgs'
        self%args(170) = 'ncunits'
        self%args(171) = 'nbest'
        self%args(172) = 'nboot'
        self%args(173) = 'ncls'
        self%args(174) = 'ncomps'
        self%args(175) = 'ndiscrete'
        self%args(176) = 'ndocs'
        self%args(177) = 'newbox'
        self%args(178) = 'newbox2'
        self%args(179) = 'nframes'
        self%args(180) = 'nmembers'
        self%args(181) = 'nnn'
        self%args(182) = 'noris'
        self%args(183) = 'nparts'
        self%args(184) = 'npeaks'
        self%args(185) = 'npix'
        self%args(186) = 'nptcls'
        self%args(187) = 'nran'
        self%args(188) = 'nrefs'
        self%args(189) = 'nrestarts'
        self%args(190) = 'nrots'
        self%args(191) = 'nspace'
        self%args(192) = 'nstates'
        self%args(193) = 'nsub'
        self%args(194) = 'nsym'
        self%args(195) = 'nthr'
        self%args(196) = 'nthr_master'
        self%args(197) = 'numlen'
        self%args(198) = 'nvalid'
        self%args(199) = 'nvars'
        self%args(200) = 'nvox'
        self%args(201) = 'offset'
        self%args(202) = 'part'
        self%args(203) = 'pcasz'
        self%args(204) = 'ppca'
        self%args(205) = 'pspecsz'
        self%args(206) = 'pspecsz_unblur'
        self%args(207) = 'pspecsz_ctffind'
        self%args(208) = 'ptcl'
        self%args(209) = 'ring1'
        self%args(210) = 'ring2'
        self%args(211) = 'spec'
        self%args(212) = 'startit'
        self%args(213) = 'state'
        self%args(214) = 'state2split'
        self%args(215) = 'stepsz'
        self%args(216) = 'szsn'
        self%args(217) = 'tofny'
        self%args(218) = 'tof'
        self%args(219) = 'top'
        self%args(220) = 'tos'
        self%args(221) = 'trsstep'
        self%args(222) = 'update'
        self%args(223) = 'which_iter'
        self%args(224) = 'xcoord'
        self%args(225) = 'ycoord'
        self%args(226) = 'xdim'
        self%args(227) = 'xdimpd'
        self%args(228) = 'ydim'
        self%args(229) = 'alpha'
        self%args(230) = 'amsklp'
        self%args(231) = 'angerr'
        self%args(232) = 'ares'
        self%args(233) = 'astigerr'
        self%args(234) = 'astigstep'
        self%args(235) = 'athres'
        self%args(236) = 'batchfrac'
        self%args(237) = 'bfac'
        self%args(238) = 'bfacerr'
        self%args(239) = 'cenlp'
        self%args(240) = 'cs'
        self%args(241) = 'ctfreslim'
        self%args(242) = 'dcrit_rel'
        self%args(243) = 'deflim'
        self%args(244) = 'defocus'
        self%args(245) = 'dens'
        self%args(246) = 'df_close'
        self%args(247) = 'df_far'
        self%args(248) = 'dferr'
        self%args(249) = 'dfmax'
        self%args(250) = 'dfmin'
        self%args(251) = 'dfsdev'
        self%args(252) = 'dose_rate'
        self%args(253) = 'dstep'
        self%args(254) = 'dsteppd'
        self%args(255) = 'e1'
        self%args(256) = 'e2'
        self%args(257) = 'e3'
        self%args(258) = 'eps'
        self%args(259) = 'extr_thresh'
        self%args(260) = 'expastig'
        self%args(261) = 'exp_time'
        self%args(262) = 'filwidth'
        self%args(263) = 'fny'
        self%args(264) = 'frac'
        self%args(265) = 'fraca'
        self%args(266) = 'fracdeadhot'
        self%args(267) = 'frac_outliers'
        self%args(268) = 'fraczero'
        self%args(269) = 'ftol'
        self%args(270) = 'gw'
        self%args(271) = 'hp'
        self%args(272) = 'hp_ctffind'
        self%args(273) = 'inner'
        self%args(274) = 'kv'
        self%args(275) = 'lam'
        self%args(276) = 'lp_dyn'
        self%args(277) = 'lp_grid'
        self%args(278) = 'lp'
        self%args(279) = 'lp_ctffind'
        self%args(280) = 'lp_pick'
        self%args(281) = 'lpmed'
        self%args(282) = 'lpstart'
        self%args(283) = 'lpstop'
        self%args(284) = 'lpvalid'
        self%args(285) = 'moldiam'
        self%args(286) = 'moment'
        self%args(287) = 'msk'
        self%args(288) = 'mul'
        self%args(289) = 'mw'
        self%args(290) = 'neigh'
        self%args(291) = 'nsig'
        self%args(292) = 'outer'
        self%args(293) = 'phranlp'
        self%args(294) = 'power'
        self%args(295) = 'rrate'
        self%args(296) = 'scale'
        self%args(297) = 'scale2'
        self%args(298) = 'sherr'
        self%args(299) = 'smpd'
        self%args(300) = 'snr'
        self%args(301) = 'thres'
        self%args(302) = 'time_per_image'
        self%args(303) = 'time_per_frame'
        self%args(304) = 'trs'
        self%args(305) = 'var'
        self%args(306) = 'width'
        self%args(307) = 'winsz'
        self%args(308) = 'xsh'
        self%args(309) = 'ysh'
        self%args(310) = 'zsh'
        self%args(311) = 'l_distr_exec'
        self%args(312) = 'l_chunk_distr'
        self%args(313) = 'doshift'
        self%args(314) = 'l_envmsk'
        self%args(315) = 'l_autoscale'
        self%args(316) = 'l_dose_weight'
        self%args(317) = 'l_innermsk'
        self%args(318) = 'l_pick'
        self%args(319) = 'l_remap_classes'
        self%args(320) = 'l_xfel'
        self%args(321) = 'vol1'
        self%args(322) = 'vol2'
        self%args(323) = 'vol3'
        self%args(324) = 'vol4'
        self%args(325) = 'vol5'
        self%args(326) = 'vol6'
        self%args(327) = 'vol7'
        self%args(328) = 'vol8'
        self%args(329) = 'vol9'
        self%args(330) = 'vol10'
        self%args(331) = 'vol11'
        self%args(332) = 'vol12'
        self%args(333) = 'vol13'
        self%args(334) = 'vol14'
        self%args(335) = 'vol15'
        self%args(336) = 'vol16'
        self%args(337) = 'vol17'
        self%args(338) = 'vol18'
        self%args(339) = 'vol19'
        self%args(340) = 'vol20'
        self%args(341) = ''
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
