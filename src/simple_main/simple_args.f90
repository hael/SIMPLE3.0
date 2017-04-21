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
        self%args(41) = 'phaseplate'
        self%args(42) = 'phrand'
        self%args(43) = 'plot'
        self%args(44) = 'readwrite'
        self%args(45) = 'restart'
        self%args(46) = 'rnd'
        self%args(47) = 'rm_outliers'
        self%args(48) = 'roalgn'
        self%args(49) = 'round'
        self%args(50) = 'shalgn'
        self%args(51) = 'shellnorm'
        self%args(52) = 'shbarrier'
        self%args(53) = 'single'
        self%args(54) = 'soften'
        self%args(55) = 'srch_inpl'
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
        self%args(67) = 'zero'
        self%args(68) = 'angastunit'
        self%args(69) = 'boxfile'
        self%args(70) = 'boxtab'
        self%args(71) = 'boxtype'
        self%args(72) = 'chunktag'
        self%args(73) = 'clsdoc'
        self%args(74) = 'comlindoc'
        self%args(75) = 'ctf'
        self%args(76) = 'cwd'
        self%args(77) = 'deftab'
        self%args(78) = 'dfunit'
        self%args(79) = 'dir'
        self%args(80) = 'dir_movies'
        self%args(81) = 'dir_reject'
        self%args(82) = 'dir_select'
        self%args(83) = 'dir_target'
        self%args(84) = 'dir_ptcls'
        self%args(85) = 'doclist'
        self%args(86) = 'endian'
        self%args(87) = 'exec_abspath'
        self%args(88) = 'exp_doc'
        self%args(89) = 'ext'
        self%args(90) = 'extrmode'
        self%args(91) = 'fbody'
        self%args(92) = 'featstk'
        self%args(93) = 'filetab'
        self%args(94) = 'fname'
        self%args(95) = 'fsc'
        self%args(96) = 'hfun'
        self%args(97) = 'hist'
        self%args(98) = 'imgkind'
        self%args(99) = 'infile'
        self%args(100) = 'label'
        self%args(101) = 'mskfile'
        self%args(102) = 'msktype'
        self%args(103) = 'opt'
        self%args(104) = 'oritab'
        self%args(105) = 'oritab2'
        self%args(106) = 'oritab3D'
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
        self%args(127) = 'unidoc'
        self%args(128) = 'vol'
        self%args(129) = 'vollist'
        self%args(130) = 'voltab'
        self%args(131) = 'voltab2'
        self%args(132) = 'wfun'
        self%args(133) = 'astep'
        self%args(134) = 'avgsz'
        self%args(135) = 'batchsz'
        self%args(136) = 'binwidth'
        self%args(137) = 'box'
        self%args(138) = 'boxconvsz'
        self%args(139) = 'boxmatch'
        self%args(140) = 'boxpd'
        self%args(141) = 'chunk'
        self%args(142) = 'chunksz'
        self%args(143) = 'class'
        self%args(144) = 'clip'
        self%args(145) = 'corner'
        self%args(146) = 'cube'
        self%args(147) = 'edge'
        self%args(148) = 'find'
        self%args(149) = 'nframesgrp'
        self%args(150) = 'fromf'
        self%args(151) = 'fromp'
        self%args(152) = 'froms'
        self%args(153) = 'fstep'
        self%args(154) = 'grow'
        self%args(155) = 'iares'
        self%args(156) = 'ind'
        self%args(157) = 'iptcl'
        self%args(158) = 'jptcl'
        self%args(159) = 'jumpsz'
        self%args(160) = 'maxits'
        self%args(161) = 'maxp'
        self%args(162) = 'minp'
        self%args(163) = 'mrcmode'
        self%args(164) = 'navgs'
        self%args(165) = 'ncunits'
        self%args(166) = 'nbest'
        self%args(167) = 'nboot'
        self%args(168) = 'ncls'
        self%args(169) = 'ncomps'
        self%args(170) = 'ndiscrete'
        self%args(171) = 'ndocs'
        self%args(172) = 'newbox'
        self%args(173) = 'newbox2'
        self%args(174) = 'nframes'
        self%args(175) = 'nmembers'
        self%args(176) = 'nnn'
        self%args(177) = 'noris'
        self%args(178) = 'nparts'
        self%args(179) = 'npeaks'
        self%args(180) = 'npix'
        self%args(181) = 'nptcls'
        self%args(182) = 'nran'
        self%args(183) = 'nrefs'
        self%args(184) = 'nrestarts'
        self%args(185) = 'nrots'
        self%args(186) = 'nspace'
        self%args(187) = 'nstates'
        self%args(188) = 'nsym'
        self%args(189) = 'nthr'
        self%args(190) = 'nthr_master'
        self%args(191) = 'numlen'
        self%args(192) = 'nvalid'
        self%args(193) = 'nvars'
        self%args(194) = 'nvox'
        self%args(195) = 'offset'
        self%args(196) = 'part'
        self%args(197) = 'pcasz'
        self%args(198) = 'ppca'
        self%args(199) = 'pspecsz'
        self%args(200) = 'pspecsz_unblur'
        self%args(201) = 'pspecsz_ctffind'
        self%args(202) = 'ptcl'
        self%args(203) = 'ring1'
        self%args(204) = 'ring2'
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
        self%args(261) = 'hp'
        self%args(262) = 'hp_ctffind'
        self%args(263) = 'inner'
        self%args(264) = 'kv'
        self%args(265) = 'lam'
        self%args(266) = 'lp_dyn'
        self%args(267) = 'lp'
        self%args(268) = 'lp_ctffind'
        self%args(269) = 'lp_pick'
        self%args(270) = 'lpmed'
        self%args(271) = 'lpstart'
        self%args(272) = 'lpstop'
        self%args(273) = 'lpvalid'
        self%args(274) = 'moldiam'
        self%args(275) = 'moment'
        self%args(276) = 'msk'
        self%args(277) = 'mul'
        self%args(278) = 'mw'
        self%args(279) = 'neigh'
        self%args(280) = 'nsig'
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
        self%args(301) = 'l_chunk_distr'
        self%args(302) = 'doautomsk'
        self%args(303) = 'doshift'
        self%args(304) = 'l_automsk'
        self%args(305) = 'l_autoscale'
        self%args(306) = 'l_dose_weight'
        self%args(307) = 'l_innermsk'
        self%args(308) = 'l_pick'
        self%args(309) = 'l_xfel'
        self%args(310) = 'vol1'
        self%args(311) = 'vol2'
        self%args(312) = 'vol3'
        self%args(313) = 'vol4'
        self%args(314) = 'vol5'
        self%args(315) = 'vol6'
        self%args(316) = 'vol7'
        self%args(317) = 'vol8'
        self%args(318) = 'vol9'
        self%args(319) = 'vol10'
        self%args(320) = 'vol11'
        self%args(321) = 'vol12'
        self%args(322) = 'vol13'
        self%args(323) = 'vol14'
        self%args(324) = 'vol15'
        self%args(325) = 'vol16'
        self%args(326) = 'vol17'
        self%args(327) = 'vol18'
        self%args(328) = 'vol19'
        self%args(329) = 'vol20'
        self%args(330) = ''
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
        spath = '/Users/creboul/Simple3'
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
