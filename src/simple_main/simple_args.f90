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
        self%args(58) = 'stream'
        self%args(59) = 'swap'
        self%args(60) = 'test'
        self%args(61) = 'tomo'
        self%args(62) = 'time'
        self%args(63) = 'trsstats'
        self%args(64) = 'use_gpu'
        self%args(65) = 'verbose'
        self%args(66) = 'vis'
        self%args(67) = 'xfel'
        self%args(68) = 'zero'
        self%args(69) = 'angastunit'
        self%args(70) = 'boxtab'
        self%args(71) = 'boxtype'
        self%args(72) = 'clsdoc'
        self%args(73) = 'comlindoc'
        self%args(74) = 'ctf'
        self%args(75) = 'cwd'
        self%args(76) = 'deftab'
        self%args(77) = 'dfunit'
        self%args(78) = 'dir'
        self%args(79) = 'dir_movies'
        self%args(80) = 'dir_reject'
        self%args(81) = 'dir_select'
        self%args(82) = 'dir_target'
        self%args(83) = 'dir_ptcls'
        self%args(84) = 'doclist'
        self%args(85) = 'endian'
        self%args(86) = 'exp_doc'
        self%args(87) = 'ext'
        self%args(88) = 'extrmode'
        self%args(89) = 'fbody'
        self%args(90) = 'featstk'
        self%args(91) = 'filetab'
        self%args(92) = 'fname'
        self%args(93) = 'fsc'
        self%args(94) = 'hfun'
        self%args(95) = 'hist'
        self%args(96) = 'imgkind'
        self%args(97) = 'infile'
        self%args(98) = 'label'
        self%args(99) = 'mskfile'
        self%args(100) = 'msktype'
        self%args(101) = 'opt'
        self%args(102) = 'oritab'
        self%args(103) = 'oritab2'
        self%args(104) = 'outfile'
        self%args(105) = 'outstk'
        self%args(106) = 'outvol'
        self%args(107) = 'ctffind_doc'
        self%args(108) = 'pcastk'
        self%args(109) = 'pdfile'
        self%args(110) = 'pgrp'
        self%args(111) = 'plaintexttab'
        self%args(112) = 'prg'
        self%args(113) = 'refine'
        self%args(114) = 'refs_msk'
        self%args(115) = 'refs'
        self%args(116) = 'speckind'
        self%args(117) = 'split_mode'
        self%args(118) = 'stk_part'
        self%args(119) = 'stk'
        self%args(120) = 'stk2'
        self%args(121) = 'stk3'
        self%args(122) = 'tomoseries'
        self%args(123) = 'vol'
        self%args(124) = 'vollist'
        self%args(125) = 'voltab'
        self%args(126) = 'voltab2'
        self%args(127) = 'wfun'
        self%args(128) = 'astep'
        self%args(129) = 'avgsz'
        self%args(130) = 'binwidth'
        self%args(131) = 'box'
        self%args(132) = 'boxconvsz'
        self%args(133) = 'boxmatch'
        self%args(134) = 'boxpd'
        self%args(135) = 'chunksz'
        self%args(136) = 'class'
        self%args(137) = 'clip'
        self%args(138) = 'corner'
        self%args(139) = 'cube'
        self%args(140) = 'edge'
        self%args(141) = 'find'
        self%args(142) = 'frameavg'
        self%args(143) = 'fromf'
        self%args(144) = 'fromp'
        self%args(145) = 'froms'
        self%args(146) = 'fstep'
        self%args(147) = 'grow'
        self%args(148) = 'iares'
        self%args(149) = 'iptcl'
        self%args(150) = 'jptcl'
        self%args(151) = 'jumpsz'
        self%args(152) = 'maxits'
        self%args(153) = 'maxp'
        self%args(154) = 'minp'
        self%args(155) = 'mrcmode'
        self%args(156) = 'navgs'
        self%args(157) = 'ncunits'
        self%args(158) = 'nbest'
        self%args(159) = 'nboot'
        self%args(160) = 'ncls'
        self%args(161) = 'ncomps'
        self%args(162) = 'ndiscrete'
        self%args(163) = 'ndocs'
        self%args(164) = 'newbox'
        self%args(165) = 'nframes'
        self%args(166) = 'nmembers'
        self%args(167) = 'nnn'
        self%args(168) = 'noris'
        self%args(169) = 'nparts'
        self%args(170) = 'npeaks'
        self%args(171) = 'npix'
        self%args(172) = 'nptcls'
        self%args(173) = 'nran'
        self%args(174) = 'nrefs'
        self%args(175) = 'nrestarts'
        self%args(176) = 'nrots'
        self%args(177) = 'nspace'
        self%args(178) = 'nstates'
        self%args(179) = 'nsym'
        self%args(180) = 'nthr'
        self%args(181) = 'nthr_master'
        self%args(182) = 'numlen'
        self%args(183) = 'nvalid'
        self%args(184) = 'nvars'
        self%args(185) = 'nvox'
        self%args(186) = 'part'
        self%args(187) = 'pcasz'
        self%args(188) = 'ppca'
        self%args(189) = 'pspecsz'
        self%args(190) = 'pspecsz_unblur'
        self%args(191) = 'pspecsz_ctffind'
        self%args(192) = 'ptcl'
        self%args(193) = 'ring1'
        self%args(194) = 'ring2'
        self%args(195) = 'set_gpu'
        self%args(196) = 'spec'
        self%args(197) = 'startit'
        self%args(198) = 'state'
        self%args(199) = 'state2split'
        self%args(200) = 'stepsz'
        self%args(201) = 'tofny'
        self%args(202) = 'tof'
        self%args(203) = 'top'
        self%args(204) = 'tos'
        self%args(205) = 'trsstep'
        self%args(206) = 'update'
        self%args(207) = 'which_iter'
        self%args(208) = 'xdim'
        self%args(209) = 'xdimpd'
        self%args(210) = 'ydim'
        self%args(211) = 'alpha'
        self%args(212) = 'amsklp'
        self%args(213) = 'angerr'
        self%args(214) = 'ares'
        self%args(215) = 'astigerr'
        self%args(216) = 'astigstep'
        self%args(217) = 'athres'
        self%args(218) = 'bfac'
        self%args(219) = 'bfacerr'
        self%args(220) = 'cenlp'
        self%args(221) = 'cs'
        self%args(222) = 'ctfreslim'
        self%args(223) = 'dcrit_rel'
        self%args(224) = 'deflim'
        self%args(225) = 'defocus'
        self%args(226) = 'dens'
        self%args(227) = 'dferr'
        self%args(228) = 'dfmax'
        self%args(229) = 'dfmin'
        self%args(230) = 'dfsdev'
        self%args(231) = 'dose_rate'
        self%args(232) = 'dstep'
        self%args(233) = 'dsteppd'
        self%args(234) = 'e1'
        self%args(235) = 'e2'
        self%args(236) = 'e3'
        self%args(237) = 'eps'
        self%args(238) = 'expastig'
        self%args(239) = 'exp_time'
        self%args(240) = 'filwidth'
        self%args(241) = 'fny'
        self%args(242) = 'frac'
        self%args(243) = 'fraca'
        self%args(244) = 'fracdeadhot'
        self%args(245) = 'fraczero'
        self%args(246) = 'ftol'
        self%args(247) = 'gw'
        self%args(248) = 'hp'
        self%args(249) = 'hp_ctffind'
        self%args(250) = 'inner'
        self%args(251) = 'kv'
        self%args(252) = 'lam'
        self%args(253) = 'lp_dyn'
        self%args(254) = 'lp'
        self%args(255) = 'lp_ctffind'
        self%args(256) = 'lp_pick'
        self%args(257) = 'lpmed'
        self%args(258) = 'lpstart'
        self%args(259) = 'lpstop'
        self%args(260) = 'lpvalid'
        self%args(261) = 'moldiam'
        self%args(262) = 'moment'
        self%args(263) = 'msk'
        self%args(264) = 'mul'
        self%args(265) = 'mw'
        self%args(266) = 'neigh'
        self%args(267) = 'outer'
        self%args(268) = 'phranlp'
        self%args(269) = 'power'
        self%args(270) = 'scale'
        self%args(271) = 'sherr'
        self%args(272) = 'smpd'
        self%args(273) = 'snr'
        self%args(274) = 'thres'
        self%args(275) = 'time_per_image'
        self%args(276) = 'time_per_frame'
        self%args(277) = 'trs'
        self%args(278) = 'var'
        self%args(279) = 'width'
        self%args(280) = 'winsz'
        self%args(281) = 'xsh'
        self%args(282) = 'ysh'
        self%args(283) = 'zsh'
        self%args(284) = 'l_distr_exec'
        self%args(285) = 'doautomsk'
        self%args(286) = 'doshift'
        self%args(287) = 'l_automsk'
        self%args(288) = 'l_dose_weight'
        self%args(289) = 'l_innermsk'
        self%args(290) = 'l_shellw'
        self%args(291) = 'l_xfel'
        self%args(292) = 'vol1'
        self%args(293) = 'vol2'
        self%args(294) = 'vol3'
        self%args(295) = 'vol4'
        self%args(296) = 'vol5'
        self%args(297) = 'vol6'
        self%args(298) = 'vol7'
        self%args(299) = 'vol8'
        self%args(300) = 'vol9'
        self%args(301) = 'vol10'
        self%args(302) = 'vol11'
        self%args(303) = 'vol12'
        self%args(304) = 'vol13'
        self%args(305) = 'vol14'
        self%args(306) = 'vol15'
        self%args(307) = 'vol16'
        self%args(308) = 'vol17'
        self%args(309) = 'vol18'
        self%args(310) = 'vol19'
        self%args(311) = 'vol20'
        self%args(312) = ''
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
