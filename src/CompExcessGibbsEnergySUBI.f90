
    !-------------------------------------------------------------------------------------------------------------
    !
    !> \file    CompExcessGibbsEnergySUBI.f90
    !> \brief   Compute the partial molar excess Gibbs energy of mixing of solution phase constituents in a
    !!          SUBI solution phase.
    !> \author  M.H.A. Piro
    !> \date    January 19, 2021
    !> \sa      CompExcessGibbsEnergy.f90
    !> \sa      CompExcessGibbsEnergyRKMP.f90
    !> \sa      CompExcessGibbsEnergyQKTO.f90
    !
    !
    ! Revisions:
    ! ==========
    !
    !   Date            Programmer      Description of change
    !   ----            ----------      ---------------------
    !   01/19/2021      M. Poschmann     Original code
    !
    !
    ! Purpose:
    ! ========
    !
    !> \details The purpose of this subroutine is to compute the partial molar excess Gibbs energy of mixing
    !! (dPartialExcessGibbs) of all constituents in a non-ideal solution phase designated as 'SUBI'
    !! (Ionic Liquid Model).
    !!
    !
    ! Pertinent variables:
    ! ====================
    !
    !> \param[in] iSolnIndex    Absolute index of a solution phase
    !
    ! nSpeciesPhase             An integec vector representing the last index of a species in a particular
    !                            solution phase
    ! nParamPhase               An integer vector representing the number of parameters for a particular phase.
    ! nSublattice               An integer scalar representing the number of sublattices associated with this
    !                            particular phase (used for convenience).
    ! nSublatticePhase          An integer vector representing the number of sublattices for each charged phase.
    ! iSPI           An integer scalar representing the relative index of the charged phase.
    ! iParam                    An integer scalar representing the index number of a parameter.
    ! iPhaseSublattice          An integer vector representing the relative index of a charged phase corresponding
    !                            to each solution phase in the system.  Thus, it is equal to zero for a phase
    !                            that does not contain any sublattices.
    ! iRegularParam             An integer matrix representing the relative indices of species mixing for a
    !                            particular parmater.
    ! iFirst             An integer scalar representing the absolute index of the first species in a phase.
    ! iLast              An integer scalar representing the absolute index of the last species in a phase.
    ! dChemicalPotential        A double real vector representing the chemical potential for every species in the
    !                            system.
    ! dMolFraction              A double real vector representing hte mole fraction of all species in the system.
    ! dSiteFraction             A double real array representing the site fraction of each constituent on each
    !                            sublattice.  The first dimension corresponds to the charged phase index, the
    !                            second dimension corresponds to the sublattice index and the third dimension
    !                            corresponds to the constituent index.
    ! dExcessGibbsParam         A double real vector representing the molar excess Gibbs energy of mixing for
    !                            each subsystem.
    ! dPartialExcessGibbs       Partial molar excess Gibbs energy of mixing of species.
    ! dMolFraction              Current estimated mole fraction.
    ! cSolnPhaseType            A character vector representing the solution phase type.
    ! iConstituentSublattice    An integer array representing the constituent index for a particular sublattice
    !                            phase.  The first dimension refers to the relative phase index for charged phases,
    !                            the second dimension represents the sublattice index and the third dimension
    !                            corresponds to the relative component index (not absolute).
    ! iFirstParam               An integer scalar representing the constituent index of the first constituent
    !                            that is being mixed for a mixing parameter.
    ! iSeconParam               An integer scalar representing the constituent index of the second constituent
    !                            that is being mixed for a mixing parameter.
    ! iSubParam                 An integer scalar representing the sublattice index corresponding to the mixing
    !                            parameter.
    !
    !-------------------------------------------------------------------------------------------------------------


subroutine CompExcessGibbsEnergySUBI(iSolnIndex)

    USE ModuleThermo
    USE ModuleThermoIO
    USE ModuleGEMSolver

    implicit none

    integer :: i, j, l, k1, l1, k2, l2, m, n, c, d, k, s
    integer :: iCi, iCj, iBi, iAi, iAj
    integer :: iSolnIndex, nSublattice, iSPI, iExponent
    integer :: iMixTypeVa , iMixTypeBi, iMixTypeAni
    integer :: iFirst, iLast
    integer, dimension(:), allocatable:: iMixType
    real(8) :: dSub1Total, dSub2Total, dydn
    real(8) :: dSum, p, q, kc1, kc2, lc1, lc2, gref, gideal, gexcess, natom, yva, dMol, dMolAtoms
    real(8), dimension(:), allocatable :: dgdc1, dgdc2, dMolDerivatives
    real(8) :: dPreFactor, f, chargeCi, chargeCj, yCi, yCj, yAi, yAj, yBi, yDi

print*,""
print*,""
print*,"                          CompExcessGibbsEnergySUBI.f90"
print*,""
print*,""

    ! Only proceed if the correct phase type is selected:
    IF_SUBL: if (cSolnPhaseType(iSolnIndex) == 'SUBI') then

        ! Define temporary variables for sake of convenience:
        iSPI = iPhaseSublattice(iSolnIndex)
        nSublattice     = nSublatticePhase(iSPI)
        iFirst          = nSpeciesPhase(iSolnIndex-1) + 1
        iLast           = nSpeciesPhase(iSolnIndex)

        if (allocated(dgdc1)) deallocate(dgdc1)
        if (allocated(dgdc2)) deallocate(dgdc2)
        if (allocated(dMolDerivatives)) deallocate(dMolDerivatives)
        if (allocated(iMixType)) deallocate(iMixType)
        allocate(dgdc1(nConstituentSublattice(iSPI,1)),dgdc2(nConstituentSublattice(iSPI,2)))
        allocate(dMolDerivatives(iLast - iFirst + 1))
        allocate(iMixType(nParamPhase(iSolnIndex)))

        ! Initialize variables:
        dSiteFraction(iSPI,1:nSublattice,1:nMaxConstituentSys) = 0D0
        dChemicalPotential(iFirst:iLast)                       = 0D0
        dPartialExcessGibbs(iFirst:iLast)                      = 0D0
        dgdc1                                                  = 0D0
        dgdc2                                                  = 0D0
        dMolDerivatives                                        = 0D0
        iMixType                                               = 0

        ! Compute site fractions on first sublattice:
        do i = iFirst, iLast
            ! Relative component index:
            m = i - iFirst + 1
            c = iConstituentSublattice(iSPI,1,m)
            d = iConstituentSublattice(iSPI,2,m)

            if (cConstituentNameSUB(iSPI,2,d) == 'Va') then
                lc2 = 1D0
            else
                lc2 = -dSublatticeCharge(iSPI,2,d)
            end if
            if (c > 0) then
                dSiteFraction(iSPI,1,c) = dSiteFraction(iSPI,1,c) + dMolFraction(i) * lc2
            end if
        end do

        ! Correct first site fraction
        dSub1Total = 0D0
        do i = 1, nConstituentSublattice(iSPI,1)
            dSub1Total = dSub1Total + dSiteFraction(iSPI,1,i)
        end do
        do i = 1, nConstituentSublattice(iSPI,1)
            dSiteFraction(iSPI,1,i) = dSiteFraction(iSPI,1,i) / dSub1Total
        end do

        ! Compute Q
        q = 0D0
        do i = 1, nConstituentSublattice(iSPI,1)
            q = q + dSublatticeCharge(iSPI,1,i) * dSiteFraction(iSPI,1,i)
        end do

        ! Compute site fractions on second sublattice:
        do i = iFirst, iLast
            ! Relative component index:
            m = i - iFirst + 1
            c = iConstituentSublattice(iSPI,2,m)
            if ((cConstituentNameSUB(iSPI,2,c) == 'Va') .OR. &
                (dSublatticeCharge(iSPI,2,c) == 0D0)) then
                ! Vacancy or neutral get scaled by Q
                dSiteFraction(iSPI,2,c) = dSiteFraction(iSPI,2,c) + dMolFraction(i)
            else
                d = iConstituentSublattice(iSPI,1,m)
                dSiteFraction(iSPI,2,c) = dSiteFraction(iSPI,2,c) + dMolFraction(i) * dSublatticeCharge(iSPI,1,d)
            end if
        end do

        ! Correct second site fraction
        dSub2Total = 0D0
        yva = 0D0
        do i = 1, nConstituentSublattice(iSPI,2)
            dSub2Total = dSub2Total + dSiteFraction(iSPI,2,i)
        end do
        do i = 1, nConstituentSublattice(iSPI,2)
            dSiteFraction(iSPI,2,i) = dSiteFraction(iSPI,2,i) / dSub2Total
            ! find site fraction of vacancies
            if (cConstituentNameSUB(iSPI,2,i) == 'Va') yva = dSiteFraction(iSPI,2,i)
        end do

        ! Compute P
        p = 0D0
        do i = 1, nConstituentSublattice(iSPI,2)
            if (cConstituentNameSUB(iSPI,2,i) == 'Va') then
                ! Use Q as charge if this constituent is vacancy
                p = p + q * dSiteFraction(iSPI,2,i)
            else
                p = p - dSublatticeCharge(iSPI,2,i) * dSiteFraction(iSPI,2,i)
            end if
        end do

        ! Compute number of moles and its derivatives
        dMol = (p + (q * (1D0 - yva)))
        do j = iFirst, iLast
            ! Relative species index:
            n = j - iFirst + 1

            ! Store constituent indices:
            l1 = iConstituentSublattice(iSPI,1,n)
            l2 = iConstituentSublattice(iSPI,2,n)

            lc1 = 1D0
            if (l1 > 0) lc1 = dSublatticeCharge(iSPI,1,l1)
            if ((cConstituentNameSUB(iSPI,2,l2) == 'Va') .OR. &
                (dSublatticeCharge(iSPI,2,l2) == 0D0)) then
                lc2 = 1D0
            else
                lc2 = -dSublatticeCharge(iSPI,2,l2)
            end if

            if (cConstituentNameSUB(iSPI,2,l2) == 'Va') then
                ! cation / vacancy
                dMolDerivatives(n) = -dSub2Total * lc1
                do i = 1, nConstituentSublattice(iSPI,1)
                    dMolDerivatives(n) = dMolDerivatives(n) + dSub2Total*dSiteFraction(iSPI,1,i)*dSublatticeCharge(iSPI,1,i)
                end do
                do i = 1, nConstituentSublattice(iSPI,2)
                    ! Only include anions (not neutrals or vacancies)
                    if (.NOT.(cConstituentNameSUB(iSPI,2,i) == 'Va') .OR. &
                        (dSublatticeCharge(iSPI,2,i) == 0D0)) &
                    dMolDerivatives(n) = dMolDerivatives(n) + dSub1Total*dSiteFraction(iSPI,2,i)*(-dSublatticeCharge(iSPI,2,i))
                end do
            else if (dSublatticeCharge(iSPI,2,l2) == 0D0) then
                ! neutral
                do i = 1, nConstituentSublattice(iSPI,2)
                    ! Only include anions (not neutrals or vacancies)
                    if (.NOT.(cConstituentNameSUB(iSPI,2,i) == 'Va') .OR. &
                        (dSublatticeCharge(iSPI,2,i) == 0D0)) &
                    dMolDerivatives(n) = dMolDerivatives(n) + dSub1Total*dSiteFraction(iSPI,2,i)*(-dSublatticeCharge(iSPI,2,i))
                end do
            else
                ! cation / anion
                dMolDerivatives(n) = -(dSub1Total + dSub2Total) * lc1 * lc2
                do i = 1, nConstituentSublattice(iSPI,1)
                    dMolDerivatives(n) = dMolDerivatives(n)+dSub2Total*lc2*dSiteFraction(iSPI,1,i)*dSublatticeCharge(iSPI,1,i)
                end do
                do i = 1, nConstituentSublattice(iSPI,2)
                    ! Only include anions (not neutrals or vacancies)
                    if (.NOT.((cConstituentNameSUB(iSPI,2,i) == 'Va') .OR. &
                    (dSublatticeCharge(iSPI,2,i) == 0D0))) &
                    dMolDerivatives(n) = dMolDerivatives(n)+dSub1Total*lc1*dSiteFraction(iSPI,2,i)*(-dSublatticeCharge(iSPI,2,i))
                end do
            end if
            dMolDerivatives(n) = dMolDerivatives(n) / (dSub1Total*dSub2Total*dMol**2)
        end do

        ! Correct the mole fractions of phase components by the site fractions of the constituents
        dSum = 0D0
        LOOP_CorrectX: do i = iFirst, iLast
            dMolFraction(i) = 1D0
            m = i - iFirst + 1

            c = iConstituentSublattice(iSPI,2,m)
            d = iConstituentSublattice(iSPI,1,m)

            if ((cConstituentNameSUB(iSPI,2,c) == 'Va') .OR. &
                (dSublatticeCharge(iSPI,2,c) == 0D0)) then
                if (d > 0) dMolFraction(i) = dMolFraction(i) * dSiteFraction(iSPI,1,d)

                if (c > 0) dMolFraction(i) = dMolFraction(i) * dSiteFraction(iSPI,2,c)

            else
                if (d > 0) dMolFraction(i) = dMolFraction(i) * dSiteFraction(iSPI,1,d) / dSublatticeCharge(iSPI,1,d)

                if (c > 0) dMolFraction(i) = dMolFraction(i) * dSiteFraction(iSPI,2,c)

            end if
            dSum = dSum + dMolFraction(i)
        end do LOOP_CorrectX

        ! Normalize mole fractions and compute number of mole atoms per mole (yes that makes sense, don't think about it)
        dMolAtoms = 0D0
        do i = iFirst, iLast

            dMolFraction(i)  = dMolFraction(i) / dSum

            m = i - iFirst + 1
            d = iConstituentSublattice(iSPI,1,m)
            c = iConstituentSublattice(iSPI,2,m)
            if ((cConstituentNameSUB(iSPI,2,c) == 'Va') .OR. &
                (dSublatticeCharge(iSPI,2,c) == 0D0)) then
                dMolAtoms = dMolAtoms + dMolFraction(i)
            else
                dMolAtoms = dMolAtoms + dMolFraction(i) * (dSublatticeCharge(iSPI,1,d) - dSublatticeCharge(iSPI,2,c))
            end if
        end do

        dStoichSublattice(iSPI,1) = p
        dStoichSublattice(iSPI,2) = q

        !---------------------------------------------------------------
        !                        EXCESS TERMS
        ! --------------------------------------------------------------
        gexcess = 0D0

        ! Loop through parameters:
        LOOP_Param: do l = nParamPhase(iSolnIndex-1) + 1, nParamPhase(iSolnIndex)
            ! Return control to the parent subroutine if there aren't any interaction parameters for this phase:
            if (nParamPhase(iSolnIndex) - nParamPhase(iSolnIndex-1) == 0) exit LOOP_Param
            ! Reinitialize temporary variable:
            dPreFactor = 1D0

            f = 0D0

            yCi = 0D0
            yCj = 0D0
            yAi = 0D0
            yAj = 0D0
            yBi = 0D0
            yDi = 0D0

            ! Store the number of constituents involved in this parameter:
            n = iRegularParam(l,1)

            ! Determine the mixing parameter type: L_Ci:Aj,Dk
            if ((iSUBIParamData(l,1) == 1) .AND. &
                (iSUBIParamData(l,2) == 3) .AND. &
                (iSUBIParamData(l,3) == 2) .AND. &
                (iSUBIParamData(l,6) == 0)) then
                ! Defines the mixing case type: L_Ci:Aj,Dk
                iMixType(l) = 1

                ! Loop through constituents associated with this parameter:
                do k = 2, n + 1
                    ! Determine constituent and sublattice indices:
                    c = MOD(iRegularParam(l,k), 10000)
                    s = iRegularParam(l,k) - c
                    s = s / 10000

                    ! Compute prefactor term:
                    dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)

                    ! Store the first and second site fractions:
                    if (k == iSUBIParamData(l,2)) then
                        ! anion - Aj
                        yAi = dSiteFraction(iSPI,s,c)

                    else if (k == iSUBIParamData(l,2) + 1) then
                        ! vacancy - Va
                        yva = dSiteFraction(iSPI,s,c)

                    end if
                end do

                ! Multiply prefactor term by excess Gibbs energy parameter:
                iExponent = iRegularParam(l,n+2)
                ! Excess Gibbs energy equation for L_Ci:Aj,Dk case
                gexcess = gexcess + dPreFactor * dExcessGibbsParam(l) * (yAi - yva)**(iExponent)

            ! Determine the mixing parameter type: L_Ci,Cj:(Va or Ak)
            else if ((iSUBIParamData(l,1) == 1) .AND. &
                     (iSUBIParamData(l,2) == 2) .AND. &
                     (iSUBIParamData(l,3) == 2)) then

                ! Loop through constituents associated with this parameter:
                do k = 2, n + 1
                    ! Determine constituent and sublattice indices:
                    c = MOD(iRegularParam(l,k), 10000)
                    s = iRegularParam(l,k) - c
                    s = s / 10000

                    ! Store the first and second site fractions:
                    if (k-1 == iSUBIParamData(l,1)) then
                        ! cation - Ci
                        yCi = dSiteFraction(iSPI,s,c)
                        ! Compute prefactor term:
                        dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)

                    else if (k == iSUBIParamData(l,2)+1) then
                        ! cation - Cj
                        yCj = dSiteFraction(iSPI,s,c)
                        ! Compute prefactor term:
                        dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)

                    !Determine if the last mixing constituent is a vacancy or anion
                    else if ((cConstituentNameSUB(iSPI,s,c) == 'Va') .AND. &
                        (k == n + 1)) then
                        ! Defines the mixing case type: L_Ci,Cj:Va
                        iMixType(l) = 2
                        ! Compute prefactor term:
                        dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)**2

                    else
                        ! Defines the mixing case type: L_Ci,Cj:Ak
                        iMixType(l) = 3
                        ! Compute prefactor term:
                        dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)

                    end if
                end do

                ! Multiply prefactor term by excess Gibbs energy parameter:
                iExponent = iRegularParam(l,n+2)

                ! Excess Gibbs energy equation for L_Ci,Cj:Va case
                if (iMixType(l) == 2) then

                    gexcess = gexcess + q * dPreFactor * dExcessGibbsParam(l) * &
                             (yCi - yCj)**(iExponent)

                ! Excess Gibbs energy equation for L_Ci,Cj:Ak case
                else if (iMixType(l) == 3) then

                    gexcess = gexcess + dPreFactor * dExcessGibbsParam(l) * &
                             (yCi - yCj)**(iExponent)

                end if
            ! Determine the mixing parameter type: L_Ci:Va,Bj
            else if ((iSUBIParamData(l,1) == 1) .AND. &
                     (iSUBIParamData(l,2) == 3) .AND. &
                     (iSUBIParamData(l,3) == 2) .AND. &
                     (iSUBIParamData(l,6) == 1)) then

                ! Defines the mixing case type: L_Ci:Va,Bj
                iMixType(l) = 4

                ! Loop through constituents associated with this parameter:
                do k = 2, n + 1
                    ! Determine constituent and sublattice indices:
                    c = MOD(iRegularParam(l,k), 10000)
                    s = iRegularParam(l,k) - c
                    s = s / 10000

                    ! Compute prefactor term:
                    dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)

                    ! Store the first and second site fractions:
                    if (k == iSUBIParamData(l,2) - 1) then
                        ! cation - Ci
                        yCi = dSiteFraction(iSPI,s,c)

                    else if (k == iSUBIParamData(l,2)) then
                        ! vacancy - Va
                        yva = dSiteFraction(iSPI,s,c)

                    else
                        ! nuetral - Bj
                        yBi = dSiteFraction(iSPI,s,c)

                    end if
                end do

                ! Multiply prefactor term by excess Gibbs energy parameter:
                iExponent = iRegularParam(l,n+2)
                ! Excess Gibbs energy equation for L_Ci:Va,Bj case
                gexcess = gexcess + q * dPreFactor * dExcessGibbsParam(l) * &
                         (yCi * yva - yBi)**(iExponent)

            ! Begining of ternary mixing cases
            ! Determine the mixing parameter type: L_Ci,Cj:Ak,Dl
            else if ((iSUBIParamData(l,1) == 2) .AND. &
                     (iSUBIParamData(l,2) == 2) .AND. &
                     (iSUBIParamData(l,3) == 2) .AND. &
                     (iSUBIParamData(l,4) == 4) .AND. &
                     (iSUBIParamData(l,5) == 2) .AND. &
                     (iSUBIParamData(l,6) == 0)) then

                ! Defines the mixing case type: L_Ci,Cj:Ak,Dl
                iMixType(l) = 11

                ! Loop through constituents associated with this parameter:
                do k = 2, n + 1
                    ! Determine constituent and sublattice indices:
                    c = MOD(iRegularParam(l,k), 10000)
                    s = iRegularParam(l,k) - c
                    s = s / 10000

                    ! Compute prefactor term:
                    dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)

                    ! Store the first and second site fractions:
                    if (k == iSUBIParamData(l,2)) then
                        ! cation - Ci
                        yCi = dSiteFraction(iSPI,s,c)

                    else if (k == iSUBIParamData(l,2) + 1) then
                        ! cation - Cj
                        yCj = dSiteFraction(iSPI,s,c)

                    else if (k == iSUBIParamData(l,2) + 2) then
                        ! anion - Ak
                        yAi = dSiteFraction(iSPI,s,c)

                    else
                        ! Dl
                        yDi = dSiteFraction(iSPI,s,c)
                    end if
                end do

                ! Multiply prefactor term by excess Gibbs energy parameter:
                iExponent = iRegularParam(l,n+2)
                ! Excess Gibbs energy equation for L_Ci,Cj:Ak,Dl case
                ! Part 1 of equation:
                if (((iExponent * 2) + 1) <= l) then
                    gexcess = gexcess + dPreFactor * dExcessGibbsParam((iExponent * 2) + 1) * &
                             (yCi - yCj)**(iExponent)
                end if
                ! Part 2 of equation:
                if ((iExponent >= 1) .AND. &
                   (iExponent * 2 <= l)) then
                    gexcess = gexcess + dPreFactor * dExcessGibbsParam(iExponent * 2) * &
                             (yAi - yDi)**(iExponent)

                end if
            !%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            ! Not properly working...
            ! Determine the mixing parameter type: L_Ci,Cj:Va,Bk
            else if ((iSUBIParamData(l,1) == 2) .AND. &
                     (iSUBIParamData(l,2) == 2) .AND. &
                     (iSUBIParamData(l,3) == 2) .AND. &
                     (iSUBIParamData(l,4) == 4) .AND. &
                     (iSUBIParamData(l,5) == 2) .AND. &
                     (iSUBIParamData(l,6) == 1)) then

                ! Defines the mixing case type: L_Ci,Cj:Va,Bk
                iMixType(l) = 12

                ! Loop through constituents associated with this parameter:
                do k = 2, n + 1
                    ! Determine constituent and sublattice indices:
                    c = MOD(iRegularParam(l,k), 10000)
                    s = iRegularParam(l,k) - c
                    s = s / 10000

                    if (k == iSUBIParamData(l,2)) then
                        ! Cation - Ci
                        yCi = dSiteFraction(iSPI,s,c)
                        ! Compute prefactor term:
                        dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)
                    else if (k == iSUBIParamData(l,2) + 1) then
                        ! Cation - Cj
                        yCj = dSiteFraction(iSPI,s,c)
                        ! Compute prefactor term:
                        dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)
                    else if (k == iSUBIParamData(l,2) + 2) then
                        ! Vacancy
                        yva = dSiteFraction(iSPI,s,c)
                        ! Compute prefactor term:
                        dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)**2
                    else if (k == iSUBIParamData(l,2) + 3) then
                        ! Neutral - Bk
                        yBi = dSiteFraction(iSPI,s,c)
                        ! Compute prefactor term:
                        dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)
                    end if
                end do

                f = (1D0 - yCi * yva - yCj * yva - yBi)/3D0
                ! Excess Gibbs energy equation for L_Ci,Cj:Va,Bk case
                if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 0) then
                    gexcess = gexcess + q * dPreFactor * (yCi * yva + f) * dExcessGibbsParam(l)
                else if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 1) then
                    gexcess = gexcess + q * dPreFactor * (yCj * yva + f) * dExcessGibbsParam(l)
                else if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 2) then
                    ! In factsage 8 - y4 is positive and Factsage 6.2 y4 is negative
                    gexcess = gexcess + q * dPreFactor * (yBi + f) * dExcessGibbsParam(l)
                else
                    print *, 'Unrecognized excess mixing term in SUBI phase ', cSolnPhaseName(iSolnIndex)
                    INFOThermo = 36
                    return
                end if
            else
                print *, 'Unrecognized excess mixing term in SUBI phase ', cSolnPhaseName(iSolnIndex)
                INFOThermo = 36
                return
            end if

            print*,"iMixType(l)",iMixType(l)
            !print*,"gexcess:", (gexcess)*dIdealConstant * dTemperature
            print*,"-------------------------"
            print*,""
        end do LOOP_Param
        !print*,"iSUBIParamData(l,2)",iSUBIParamData(l,2) - 1
        !print*,"dSiteFraction(iSPI,s,c)",dSiteFraction(iSPI,s,c)

        !---------------------------------------------------------------
        !                      DERIVED EXCESS TERMS
        ! --------------------------------------------------------------

        ! Loop through parameters:
        LOOP_Param_Derivatives: do l = nParamPhase(iSolnIndex-1) + 1, nParamPhase(iSolnIndex)
            ! Return control to the parent subroutine if there aren't any interaction parameters for this phase:
            if (nParamPhase(iSolnIndex) - nParamPhase(iSolnIndex-1) == 0) exit LOOP_Param_Derivatives

            ! Reinitialize temporary variable:
            dPreFactor = 1D0

            f = 0D0

            chargeCi = 0D0
            chargeCj = 0D0

            iMixTypeVa = 0
            iMixTypeBi = 0
            iMixTypeAni = 0

            iAi = 0
            iAj = 0
            iBi = 0
            iCi = 0
            iCj = 0

            yCi = 0D0
            yCj = 0D0
            yAi = 0D0
            yAj = 0D0
            yBi = 0D0
            yDi = 0D0

            ! Store the number of constituents involved in this parameter:
            n = iRegularParam(l,1)

            ! Determine the mixing parameter type
            ! This is Case -> L_Ci:Aj,Dk where Dk is a vacancy, neutral or anion
            if (iMixType(l) == 1) then
                ! Loop through constituents associated with this parameter:
                do k = 2, n + 1
                    ! Determine constituent and sublattice indices:
                    c = MOD(iRegularParam(l,k), 10000)
                    s = iRegularParam(l,k) - c
                    s = s / 10000

                    ! Establishing the site fractions for the L_Ci:Aj,Dk cases
                    if (k == iSUBIParamData(l,2) - 1) then
                        ! cation - Ci
                        yCi = dSiteFraction(iSPI,s,c)
                        iCi = c

                    else if (k == iSUBIParamData(l,2)) then
                        ! anion - Aj
                        yAi = dSiteFraction(iSPI,s,c)
                        iAi = c

                    else
                        ! Determining if Dl equals a vacancy, neutral or anion
                        if (cConstituentNameSUB(iSPI,s,c) == 'Va') then
                            ! vacancy case
                            iMixTypeVa = 1
                        else if (dSublatticeCharge(iSPI,s,c) == 0D0) then
                            ! neutral case
                            iMixTypeBi = 1
                            iBi = c
                        else
                            ! anion case
                            iMixTypeAni = 1

                        end if
                        ! Dl
                        yDi = dSiteFraction(iSPI,s,c)

                    end if
                    ! L term exponent value
                    iExponent = iRegularParam(l,n+2)
                end do

                ! Chemical potential with respect to the first sublattice
                do i = 1, nConstituentSublattice(iSPI,1)
                    if (i == iCi) then
                        dgdc1(i) = dgdc1(i) + yAi * yDi * dExcessGibbsParam(l) * (yAi - yDi)**(iExponent)
                    end if
                end do

                ! Avoiding a situation with 0^(-1)
                if ((yAi - yDi) /= 0D0) then

                    ! Chemical potential with respect to the second sublattice
                    do i = 1, nConstituentSublattice(iSPI,2)

                        if ((i == iBi) .AND. &
                            (iMixTypeBi == 1)) then
                            ! neutral
                            dgdc2(i) = dgdc2(i) + yCi * yAi * dExcessGibbsParam(l) * (yAi - yDi)**(iExponent)

                            dgdc2(i) = dgdc2(i) + yCi * yAi * yDi * dExcessGibbsParam(l) * &
                                       iExponent * (yAi - yDi)**(iExponent - 1) * (-1)

                        else if ((cConstituentNameSUB(iSPI,2,i) == 'Va') .AND. &
                            (iMixTypeVa == 1)) then
                            ! cation / vacancy
                            dgdc2(i) = dgdc2(i) + yCi * yAi * dExcessGibbsParam(l) * (yAi - yDi)**(iExponent)

                            dgdc2(i) = dgdc2(i) + yCi * yAi * yDi * dExcessGibbsParam(l) * &
                                       iExponent * (yAi - yDi)**(iExponent - 1) * (-1)

                        else if (i == iAi) then
                            ! cation / anion
                            dgdc2(i) = dgdc2(i) + yCi * yDi * dExcessGibbsParam(l) * (yAi - yDi)**(iExponent)

                            dgdc2(i) = dgdc2(i) + yCi * yAi * yDi * dExcessGibbsParam(l) * &
                                       iExponent * (yAi - yDi)**(iExponent - 1) * (1)

                            if ((iMixTypeAni == 1)) then
                                ! If D_k is an anion
                                dgdc2(i) = dgdc2(i) + yCi * yAi * dExcessGibbsParam(l) * (yAi - yDi)**(iExponent)

                                dgdc2(i) = dgdc2(i) + yCi * yAi * yDi * dExcessGibbsParam(l) * &
                                           iExponent * (yAi - yDi)**(iExponent - 1) * (-1)
                            end if
                        end if
                    end do
                end if

            ! Determine the mixing parameter type
            ! This is Case -> L_Ci,Cj:Va
            else if (iMixType(l) == 2) then
                ! Loop through constituents associated with this parameter:
                do k = 2, n + 1
                    ! Determine constituent and sublattice indices:
                    c = MOD(iRegularParam(l,k), 10000)
                    s = iRegularParam(l,k) - c
                    s = s / 10000

                    ! Establishing the site fractions for this case
                    if (k-1 == iSUBIParamData(l,1)) then
                        ! Cation - Ci
                        yCi = dSiteFraction(iSPI,s,c)
                        iCi = c
                        chargeCi = dSublatticeCharge(iSPI,s,c)

                    else if (k == iSUBIParamData(l,2) + 1) then
                        ! Cation - Cj
                        yCj = dSiteFraction(iSPI,s,c)
                        iCj = c
                        chargeCj = dSublatticeCharge(iSPI,s,c)

                    else
                        ! vacancy
                        yva = dSiteFraction(iSPI,s,c)

                    end if
                    iExponent = iRegularParam(l,n+2)
                end do

                ! Avoiding a situation with 0^(-1)
                if ((yCi - yCj) /= 0) then

                    ! First sublattice - Cation:vacancy contributions
                    do i = 1, nConstituentSublattice(iSPI,1)

                        ! Derivative with respect to Ci
                        if (i == iCi) then
                            dgdc1(i) = dgdc1(i) + q * yCj * yva**2 * dExcessGibbsParam(l) * &
                                      (yCi - yCj)**(iExponent)

                            dgdc1(i) = dgdc1(i) + chargeCi * yCi * yCj * yva**2 * dExcessGibbsParam(l) * &
                                      (yCi - yCj)**(iExponent)

                            dgdc1(i) = dgdc1(i) + q * yCi * yCj * yva**2 * dExcessGibbsParam(l) * &
                                   iExponent * (yCi - yCj)**(iExponent - 1) * (1)

                        ! Derivative with respect to Cj
                        else if (i == iCj) then
                            dgdc1(i) = dgdc1(i) + q * yCi * yva**2 * dExcessGibbsParam(l) * &
                                      (yCi - yCj)**(iExponent)

                            dgdc1(i) = dgdc1(i) + chargeCj * yCi * yCj * yva**2 * dExcessGibbsParam(l) * &
                                      (yCi - yCj)**(iExponent)

                            dgdc1(i) = dgdc1(i) + q * yCi * yCj * yva**2 * dExcessGibbsParam(l) * &
                                       iExponent * (yCi - yCj)**(iExponent - 1) * (-1)

                        end if
                    end do
                end if

                ! Second sublattice - Cation:vacancy contributions
                do i = 1, nConstituentSublattice(iSPI,2)
                    if (cConstituentNameSUB(iSPI,2,i) == 'Va') then
                        dgdc2(i) = dgdc2(i) + q * yCi * yCj * 2 * yva * dExcessGibbsParam(l) * &
                                  (yCi - yCj)**(iExponent)
                    end if
                end do


            ! Determine the mixing parameter type
            ! This is Case -> L_Ci,Cj:Ak
            else if (iMixType(l) == 3) then
                ! Loop through constituents associated with this parameter:
                do k = 2, n + 1
                    ! Determine constituent and sublattice indices:
                    c = MOD(iRegularParam(l,k), 10000)
                    s = iRegularParam(l,k) - c
                    s = s / 10000

                    ! Establishing the site fractions for this case
                    if (k-1 == iSUBIParamData(l,1)) then
                        ! Cation - Ci
                        yCi = dSiteFraction(iSPI,s,c)
                        iCi = c

                    else if (k == iSUBIParamData(l,2) + 1) then
                        ! Cation - Cj
                        yCj = dSiteFraction(iSPI,s,c)
                        iCj = c

                    else
                        ! Anion - Ak
                        yAi = dSiteFraction(iSPI,s,c)
                        iAi = c

                    end if
                        iExponent = iRegularParam(l,n+2)
                end do

                ! Avoiding a situation with 0^(-1)
                if ((yCi - yCj) /= 0) then

                    ! First sublattice - Cation:vacancy contributions
                    do i = 1, nConstituentSublattice(iSPI,1)

                        ! Derivative with respect to Ci
                        if (i == iCi) then

                            dgdc1(i) = dgdc1(i) + yCj * yAi * dExcessGibbsParam(l) * &
                                      (yCi - yCj)**(iExponent)

                            dgdc1(i) = dgdc1(i) + yCi * yCj * yAi * dExcessGibbsParam(l) * &
                                       iExponent * (yCi - yCj)**(iExponent - 1) * (1)

                        ! Derivative with respect to Cj
                        else if (i == iCj) then

                            dgdc1(i) = dgdc1(i) + yCi * yAi * dExcessGibbsParam(l) * &
                                      (yCi - yCj)**(iExponent)

                            dgdc1(i) = dgdc1(i) + yCi * yCj * yAi * dExcessGibbsParam(l) * &
                                       iExponent * (yCi - yCj)**(iExponent - 1) * (-1)

                        end if
                    end do
                end if

                ! Second sublattice - Cation:vacancy contributions
                do i = 1, nConstituentSublattice(iSPI,2)
                    if (i == iAi) then
                        dgdc2(i) = dgdc2(i) + yCi * yCj * dExcessGibbsParam(l) * &
                                  (yCi - yCj)**(iExponent)

                    end if
                end do

            ! Determine the mixing parameter type
            ! This is Case -> L_Ci:Va,Bj
            else if (iMixType(l) == 4) then

                ! Loop through constituents associated with this parameter:
                do k = 2, n + 1
                    ! Determine constituent and sublattice indices:
                    c = MOD(iRegularParam(l,k), 10000)
                    s = iRegularParam(l,k) - c
                    s = s / 10000

                    ! Store the first and second site fractions:
                    if (k == iSUBIParamData(l,2) - 1) then
                        ! cation - Ci
                        yCi = dSiteFraction(iSPI,s,c)
                        iCi = c
                        chargeCi = dSublatticeCharge(iSPI,s,c)

                    else if (k == iSUBIParamData(l,2)) then
                        ! vacancy - Va
                        yva = dSiteFraction(iSPI,s,c)

                    else
                        ! neutral - Bj
                        yBi = dSiteFraction(iSPI,s,c)
                        iBi = c

                    end if
                    ! Multiply prefactor term by excess Gibbs energy parameter:
                    iExponent = iRegularParam(l,n+2)
                end do

                ! Avoiding a situation with 0^(-1)
                if ((yCi * yva - yBi) /= 0) then

                    ! First sublattice
                    do i = 1, nConstituentSublattice(iSPI,1)
                        if (i == iCi) then
                            ! cation - Ci
                            dgdc1(i) = dgdc1(i) + q * yva * yBi * dExcessGibbsParam(l) * &
                                      (yCi * yva - yBi)**(iExponent)

                            dgdc1(i) = dgdc1(i) + chargeCi * yCi * yva * yBi * dExcessGibbsParam(l) * &
                                      (yCi * yva - yBi)**(iExponent)

                            dgdc1(i) = dgdc1(i) + q * yCi * yva * yBi * dExcessGibbsParam(l) * yva * &
                                       iExponent * (yCi * yva - yBi)**(iExponent - 1)

                        end if
                    end do

                    ! Second sublattice
                    do i = 1, nConstituentSublattice(iSPI,2)
                        if (cConstituentNameSUB(iSPI,2,i) == 'Va') then
                            ! vacancy contributions
                            dgdc2(i) = dgdc2(i) + q * yCi * yBi * dExcessGibbsParam(l) * &
                                      (yCi * yva - yBi)**(iExponent)

                            dgdc2(i) = dgdc2(i) + q * yCi * yva * yBi * dExcessGibbsParam(l) * yCi * &
                                       iExponent * (yCi * yva - yBi)**(iExponent - 1)

                        else if (i == iBi) then
                            ! neutral contributions
                            dgdc2(i) = dgdc2(i) + q * yCi * yva * dExcessGibbsParam(l) * &
                                      (yCi * yva - yBi)**(iExponent)

                            dgdc2(i) = dgdc2(i) + q * yCi * yva * yBi * dExcessGibbsParam(l) * (-1) * &
                                       iExponent * (yCi * yva - yBi)**(iExponent - 1)
                        end if
                    end do
                end if

            ! Determine the mixing parameter type
            ! This is Case -> L_Ci,Cj:Ak,Dl
            else if (iMixType(l) == 11) then
                ! Loop through constituents associated with this parameter:
                do k = 2, n + 1
                    ! Determine constituent and sublattice indices:
                    c = MOD(iRegularParam(l,k), 10000)
                    s = iRegularParam(l,k) - c
                    s = s / 10000

                    ! Compute prefactor term:
                    dPreFactor = dPreFactor * dSiteFraction(iSPI,s,c)

                    ! Store the first and second site fractions:
                    if (k == iSUBIParamData(l,2)) then
                        ! Cation - Ci
                        yCi = dSiteFraction(iSPI,s,c)
                        iCi = c

                    else if (k == iSUBIParamData(l,2) + 1) then
                        ! Cation - Cj
                        yCj = dSiteFraction(iSPI,s,c)
                        iCj = c

                    else if (k == iSUBIParamData(l,2) + 2) then
                        ! Anion - Ai
                        yAi = dSiteFraction(iSPI,s,c)
                        iAi = c

                    else
                        if (cConstituentNameSUB(iSPI,s,c) == 'Va') then
                            ! Vacancy - Va
                            iMixTypeVa = 1
                        else if (dSublatticeCharge(iSPI,s,c) == 0D0) then
                            ! Nuetral
                            iBi = c
                            iMixTypeBi = 1
                        else
                            ! Anion - Aj
                            iMixTypeAni = 1
                        end if

                        ! Dl
                        yDi = dSiteFraction(iSPI,s,c)

                    end if
                end do

                ! Multiply prefactor term by excess Gibbs energy parameter:
                iExponent = iRegularParam(l,n+2)

                ! Avoiding a situation with 0^(-1)
                if ((yCi - yCj) /= 0) then

                    do i = 1, nConstituentSublattice(iSPI,1)

                        ! Derivative with respect to Ci
                        if (i == iCi) then

                            if (((iExponent * 2) + 1) <= l) then
                                ! Part 1 of derivation
                                dgdc1(i) = dgdc1(i) + yCj * yAi * yDi * dExcessGibbsParam((iExponent * 2) + 1) * &
                                          (yCi - yCj)**(iExponent)
                                ! Part 3 of derivation
                                dgdc1(i) = dgdc1(i) + yCi * yCj * yAi * yDi * dExcessGibbsParam((iExponent * 2) + 1) * &
                                           1 * iExponent * (yCi - yCj)**(iExponent - 1)
                            end if

                            if ((iExponent >= 1) .AND. &
                                (iExponent * 2 <= l)) then
                                ! Part 2 of derivation
                                dgdc1(i) = dgdc1(i) + yCj * yAi * yDi * dExcessGibbsParam(iExponent * 2) * &
                                          (yAi - yDi)**(iExponent)
                            end if

                        ! Derivative with respect to Cj
                        else if (i == iCj) then

                            if (((iExponent * 2) + 1) <= l) then
                                ! Part 1 of derivation
                                dgdc1(i) = dgdc1(i) + yCi * yAi * yDi * dExcessGibbsParam((iExponent * 2) + 1) * &
                                          (yCi - yCj)**(iExponent)
                                ! Part 3 of derivation
                                dgdc1(i) = dgdc1(i) + yCi * yCj * yAi * yDi * dExcessGibbsParam((iExponent * 2) + 1) * &
                                          (-1) * iExponent * (yCi - yCj)**(iExponent - 1)
                            end if

                            if ((iExponent >= 1) .AND. &
                                (iExponent * 2 <= l)) then
                                ! Part 2 of derivation
                                dgdc1(i) = dgdc1(i) + yCi * yAi * yDi * dExcessGibbsParam(iExponent * 2) * &
                                          (yAi - yDi)**(iExponent)
                            end if
                        end if
                    end do
                end if

                ! Avoiding a situation with 0^(-1)
                if ((yAi - yDi) /= 0) then

                    ! Chemical potential with respect to the second sublattice
                    do i = 1, nConstituentSublattice(iSPI,2)

                        !! When Dl = Al or Bl - Cases untested... %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                        ! If Dl is and neutral:
                        if ((i == iBi) .AND. &
                            (iMixTypeBi == 1)) then
                            ! neutral
                            if (((iExponent * 2) + 1) <= l) then
                                ! Part 1 of derivation
                                dgdc2(i) = dgdc2(i) + yCi * yCj * yAi * dExcessGibbsParam((iExponent * 2) + 1) * &
                                          (yCi - yCj)**(iExponent)
                            end if

                            if ((iExponent >= 1) .AND. &
                                (iExponent * 2 <= l)) then
                                ! Part 2 of derivation
                                dgdc2(i) = dgdc2(i) + yCi * yCj * yAi * dExcessGibbsParam(iExponent * 2) * &
                                          (yAi - yDi)**(iExponent)
                                ! Part 3 of derivation
                                dgdc2(i) = dgdc2(i) + yCi * yCj * yAi * yDi * dExcessGibbsParam(iExponent * 2) * &
                                          (-1) * iExponent * (yAi - yDi)**(iExponent - 1)
                            end if

                        ! If Dl is and vacancy:
                        else if ((cConstituentNameSUB(iSPI,2,i) == 'Va') .AND. &
                            (iMixTypeVa == 1)) then
                            ! cation / vacancy
                            if (((iExponent * 2) + 1) <= l) then
                                ! Part 1 of derivation
                                dgdc2(i) = dgdc2(i) + yCi * yCj * yAi * dExcessGibbsParam((iExponent * 2) + 1) * &
                                          (yCi - yCj)**(iExponent)
                            end if

                            if ((iExponent >= 1) .AND. &
                                (iExponent * 2 <= l)) then
                                ! Part 2 of derivation
                                dgdc2(i) = dgdc2(i) + yCi * yCj * yAi * dExcessGibbsParam(iExponent * 2) * &
                                          (yAi - yDi)**(iExponent)
                                ! Part 3 of derivation
                                dgdc2(i) = dgdc2(i) + yCi * yCj * yAi * yDi * dExcessGibbsParam(iExponent * 2) * &
                                          (-1) * iExponent * (yAi - yDi)**(iExponent - 1)
                            end if

                        else if (i == iAi) then
                            ! cation / anion
                            if (((iExponent * 2) + 1) <= l) then
                                ! Part 1 of derivation
                                dgdc2(i) = dgdc2(i) + yCi * yCj * yDi * dExcessGibbsParam((iExponent * 2) + 1) * &
                                          (yCi - yCj)**(iExponent)
                            end if

                            if ((iExponent >= 1) .AND. &
                                (iExponent * 2 <= l)) then
                                ! Part 2 of derivation
                                dgdc2(i) = dgdc2(i) + yCi * yCj * yDi * dExcessGibbsParam(iExponent * 2) * &
                                          (yAi - yDi)**(iExponent)
                                ! Part 3 of derivation
                                dgdc2(i) = dgdc2(i) + yCi * yCj * yAi * yDi * dExcessGibbsParam(iExponent * 2) * &
                                          (1) * iExponent * (yAi - yDi)**(iExponent - 1)
                            end if

                            ! If Dl is and anion:
                            if (iMixTypeAni == 1) then
                                ! cation / anion
                                if (((iExponent * 2) + 1) <= l) then
                                    ! Part 1 of derivation
                                    dgdc2(i) = dgdc2(i) + yCi * yCj * yAi * dExcessGibbsParam((iExponent * 2) + 1) * &
                                              (yCi - yCj)**(iExponent)
                                end if

                                if ((iExponent >= 1) .AND. &
                                    (iExponent * 2 <= l)) then
                                    ! Part 2 of derivation
                                    dgdc2(i) = dgdc2(i) + yCi * yCj * yAi * dExcessGibbsParam(iExponent * 2) * &
                                              (yAi - yDi)**(iExponent)
                                    ! Part 3 of derivation
                                    dgdc2(i) = dgdc2(i) + yCi * yCj * yAi * yDi * dExcessGibbsParam(iExponent * 2) * &
                                              (-1) * iExponent * (yAi - yDi)**(iExponent - 1)
                                end if
                            end if
                        end if
                    end do
                end if
            !%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            ! Not properly working
            ! Determine the mixing parameter type
            ! This is Case -> L_Ci,Cj:Va,Bk
            else if (iMixType(l) == 12) then
                ! Loop through constituents associated with this parameter:
                do k = 2, n + 1
                    ! Determine constituent and sublattice indices:
                    c = MOD(iRegularParam(l,k), 10000)
                    s = iRegularParam(l,k) - c
                    s = s / 10000

                    if (k == iSUBIParamData(l,2)) then
                        ! Cation - Ci
                        yCi = dSiteFraction(iSPI,s,c)
                        iCi = c
                        chargeCi = dSublatticeCharge(iSPI,s,c)

                    else if (k == iSUBIParamData(l,2) + 1) then
                        ! Cation - Cj
                        yCj = dSiteFraction(iSPI,s,c)
                        iCj = c
                        chargeCj = dSublatticeCharge(iSPI,s,c)

                    else if (k == iSUBIParamData(l,2) + 2) then
                        ! Vacancy
                        yva = dSiteFraction(iSPI,s,c)

                    else if (k == iSUBIParamData(l,2) + 3) then
                        ! Neutral - Bk
                        yBi = dSiteFraction(iSPI,s,c)
                        iBi = c

                    end if
                end do

                f = (1D0 - yCi * yva - yCj * yva - yBi)/3D0

                do i = 1, nConstituentSublattice(iSPI,1)

                    ! Derivative with respect to Ci
                    if (i == iCi) then
                        print*,"l",l
                        print*,"dgdc1(i) Ci - 0",dgdc1(i)*dIdealConstant * dTemperature
                        ! Chemical potential equation for L_Ci,Cj:Va,Bk case
                        if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 0) then
                            dgdc1(i) = dgdc1(i) + q * yCj * (yva**2) * yBi * (yCi * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Ci - 1",dgdc1(i)*dIdealConstant * dTemperature
                            ! adding a negative charge works for some random reason idk why...
                            dgdc1(i) = dgdc1(i) + (-chargeCi) * yCi * yCj * (yva**2) * yBi * (yCi * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Ci - 2",dgdc1(i)*dIdealConstant * dTemperature
                            dgdc1(i) = dgdc1(i) + q * yCi * yCj * (yva**2) * yBi * (2D0 / 3D0 * yva) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Ci - 3",dgdc1(i)*dIdealConstant * dTemperature

                        else if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 1) then
                            dgdc1(i) = dgdc1(i) + q * yCj * (yva**2) * yBi * (yCj * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Ci - 4",dgdc1(i)*dIdealConstant * dTemperature
                            dgdc1(i) = dgdc1(i) + chargeCi * yCi * yCj * (yva**2) * yBi * (yCj * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Ci - 5",dgdc1(i)*dIdealConstant * dTemperature
                            dgdc1(i) = dgdc1(i) + q * yCi * yCj * (yva**2) * yBi * (-1D0 / 3D0 * yva) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Ci - 6",dgdc1(i)*dIdealConstant * dTemperature

                        else if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 2) then
                            dgdc1(i) = dgdc1(i) + q * yCj * (yva**2) * yBi * (yBi + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Ci - 7",dgdc1(i)*dIdealConstant * dTemperature
                            dgdc1(i) = dgdc1(i) + chargeCi * yCi * yCj * (yva**2) * yBi * (yBi + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Ci - 8",dgdc1(i)*dIdealConstant * dTemperature
                            dgdc1(i) = dgdc1(i) + q * yCi * yCj * (yva**2) * yBi * (-1D0 / 3D0 * yva) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Ci - 9",dgdc1(i)*dIdealConstant * dTemperature

                        else if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 3) then
                            print *, 'Unrecognized excess mixing term in SUBI phase ', cSolnPhaseName(iSolnIndex)
                            INFOThermo = 36
                            return

                        end if
                        print*,""

                        ! Derivative with respect to Cj
                    else if (i == iCj) then
                        print*,"dgdc1(i) Cj - 0",dgdc1(i)*dIdealConstant * dTemperature
                        ! Chemical potential equation for L_Ci,Cj:Va,Bk case
                        if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 0) then
                            dgdc1(i) = dgdc1(i) + q * yCi * (yva**2) * yBi * (yCi * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Cj - 1",dgdc1(i)*dIdealConstant * dTemperature
                            dgdc1(i) = dgdc1(i) + chargeCj * yCi * yCj * (yva**2) * yBi * (yCi * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Cj - 2",dgdc1(i)*dIdealConstant * dTemperature
                            dgdc1(i) = dgdc1(i) + q * yCi * yCj * (yva**2) * yBi * (-1D0 / 3D0 * yva) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Cj - 3",dgdc1(i)*dIdealConstant * dTemperature

                        else if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 1) then
                            dgdc1(i) = dgdc1(i) + q * yCi * (yva**2) * yBi * (yCj * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Cj - 4",dgdc1(i)*dIdealConstant * dTemperature
                            ! Had to do the weird negative charge thing here too
                            dgdc1(i) = dgdc1(i) + (-chargeCj) * yCi * yCj * (yva**2) * yBi * (yCj * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Cj - 5",dgdc1(i)*dIdealConstant * dTemperature
                            dgdc1(i) = dgdc1(i) + q * yCi * yCj * (yva**2) * yBi * (2D0 / 3D0 * yva) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Cj - 6",dgdc1(i)*dIdealConstant * dTemperature

                        else if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 2) then
                            dgdc1(i) = dgdc1(i) + q * yCi * (yva**2) * yBi * (yBi + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Cj - 7",dgdc1(i)*dIdealConstant * dTemperature
                            dgdc1(i) = dgdc1(i) + chargeCj * yCi * yCj * (yva**2) * yBi * (yBi + f) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Cj - 8",dgdc1(i)*dIdealConstant * dTemperature
                            dgdc1(i) = dgdc1(i) + q * yCi * yCj * (yva**2) * yBi * (-1D0 / 3D0 * yva) * dExcessGibbsParam(l)
                            print*,"dgdc1(i) Cj - 9",dgdc1(i)*dIdealConstant * dTemperature

                        else
                            print *, 'Unrecognized excess mixing term in SUBI phase ', cSolnPhaseName(iSolnIndex)
                            INFOThermo = 36
                            return

                        end if
                        print*,""
                    end if
                end do

                do i = 1, nConstituentSublattice(iSPI,2)

                    ! Derivative with respect to Bk
                    if (i == iBi) then
                        print*,"dgdc2(i) Bk - 0",dgdc2(i)*dIdealConstant * dTemperature
                        ! Chemical potential equation for L_Ci,Cj:Va,Bk case
                        if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 0) then
                            dgdc2(i) = dgdc2(i) + q * yCi * yCj * (yva**2) * (yCi * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Bk - 1",dgdc2(i)*dIdealConstant * dTemperature
                            dgdc2(i) = dgdc2(i) + q * yCi * yCj * (yva**2) * yBi * (-1D0 / 3D0) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Bk - 2",dgdc2(i)*dIdealConstant * dTemperature

                        else if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 1) then
                            dgdc2(i) = dgdc2(i) + q * yCi * (yva**2) * (yCj * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Bk - 3",dgdc2(i)*dIdealConstant * dTemperature
                            dgdc2(i) = dgdc2(i) + q * yCi * yCj * (yva**2) * yBi * (-1D0 / 3D0) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Bk - 4",dgdc2(i)*dIdealConstant * dTemperature

                        else if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 2) then
                            dgdc2(i) = dgdc2(i) + q * yCi * (yva**2) * (yBi + f) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Bk - 5",dgdc2(i)*dIdealConstant * dTemperature
                            dgdc2(i) = dgdc2(i) + q * yCi * yCj * (yva**2) * yBi * (2D0 / 3D0) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Bk - 6",dgdc2(i)*dIdealConstant * dTemperature

                        else
                            print *, 'Unrecognized excess mixing term in SUBI phase ', cSolnPhaseName(iSolnIndex)
                            INFOThermo = 36
                            return

                        end if
                        print*,""

                    ! Derivative with respect to Va
                    else if (cConstituentNameSUB(iSPI,2,i) == 'Va') then
                        print*,"dgdc2(i) Va - 0",dgdc2(i)*dIdealConstant * dTemperature
                        ! Chemical potential equation for L_Ci,Cj:Va,Bk case
                        if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 0) then
                            dgdc2(i) = dgdc2(i) + q * yCi * yCj * (2D0*yva) * yBi * (yCi * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Va - 1",dgdc2(i)*dIdealConstant * dTemperature
                            dgdc2(i) = dgdc2(i) + q * yCi * yCj * (yva**2) * yBi * (yCi - (yCi+yCj) / 3D0) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Va - 2",dgdc2(i)*dIdealConstant * dTemperature

                        else if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 1) then
                            dgdc2(i) = dgdc2(i) + q * yCi * (2*yva) * yBi * (yCj * yva + f) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Va - 3",dgdc2(i)*dIdealConstant * dTemperature
                            dgdc2(i) = dgdc2(i) + q * yCi * yCj * (yva**2) * yBi * (yCj - (yCi+yCj) / 3D0) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Va - 4",dgdc2(i)*dIdealConstant * dTemperature

                        else if (iRegularParam(l,(iRegularParam(l,1) + 2)) == 2) then
                            dgdc2(i) = dgdc2(i) + q * yCi * (2D0*yva) * yBi * (yBi + f) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Va - 5",dgdc2(i)*dIdealConstant * dTemperature
                            dgdc2(i) = dgdc2(i) + q * yCi * yCj * (yva**2) * yBi * (-(yCi+yCj) / 3D0) * dExcessGibbsParam(l)
                            print*,"dgdc2(i) Va - 6",dgdc2(i)*dIdealConstant * dTemperature

                        else
                            print *, 'Unrecognized excess mixing term in SUBI phase ', cSolnPhaseName(iSolnIndex)
                            INFOThermo = 36
                            return

                        end if
                        print*,""
                    end if
                end do

            else
              print *, 'Unrecognized excess mixing term in SUBI phase ', cSolnPhaseName(iSolnIndex)
              INFOThermo = 36
              return

            end if

        end do LOOP_Param_Derivatives

        ! REFERENCE GIBBS ENERGY AND IDEAL MIXING
        ! ---------------------------------------
        gref = 0D0
        do j = iFirst, iLast
            ! Relative species index:
            n = j - iFirst + 1

            ! Store constituent indices:
            l1 = iConstituentSublattice(iSPI,1,n)
            l2 = iConstituentSublattice(iSPI,2,n)

            if (cConstituentNameSUB(iSPI,2,l2) == 'Va') then
                ! cation / vacancy
                gref = gref + q * dSiteFraction(iSPI,1,l1) * dSiteFraction(iSPI,2,l2) * dStdGibbsEnergy(j)
            else if (dSublatticeCharge(iSPI,2,l2) == 0D0) then
                ! neutral
                gref = gref + q * dSiteFraction(iSPI,2,l2) * dStdGibbsEnergy(j)
            else
                ! cation / anion
                gref = gref + dSiteFraction(iSPI,1,l1) * dSiteFraction(iSPI,2,l2) * dStdGibbsEnergy(j)
            end if
        end do

        gideal = 0D0
        do i = 1, nConstituentSublattice(iSPI,1)
            gideal = gideal + p * dSiteFraction(iSPI,1,i) * DLOG(dSiteFraction(iSPI,1,i))
        end do

        do i = 1, nConstituentSublattice(iSPI,2)
            gideal = gideal + q * dSiteFraction(iSPI,2,i) * DLOG(dSiteFraction(iSPI,2,i))
        end do

        print*,"p",p,"   q",q
        print*,"gexcess 02",gexcess*dIdealConstant * dTemperature
        print*,"gref+gideal:", (gref+gideal)*dIdealConstant * dTemperature
        print*,"gref+gideal+gexcess:", (gref+gideal+gexcess)*dIdealConstant * dTemperature
        print*,""

        ! For Sublattice Number 1
        do i = 1, nConstituentSublattice(iSPI,1)
            lc1 = dSublatticeCharge(iSPI,1,i)
            ! Reference
            do j = iFirst, iLast
                ! Relative species index:
                n = j - iFirst + 1
                ! Store constituent indices:
                l1 = iConstituentSublattice(iSPI,1,n)
                l2 = iConstituentSublattice(iSPI,2,n)

                if (cConstituentNameSUB(iSPI,2,l2) == 'Va') then
                    ! cation / vacancy
                    if (i == l1) dgdc1(i) = dgdc1(i) + q * dSiteFraction(iSPI,2,l2) * dStdGibbsEnergy(j)
                    dgdc1(i) = dgdc1(i) + lc1 * dSiteFraction(iSPI,1,l1) * dSiteFraction(iSPI,2,l2) * dStdGibbsEnergy(j)
                else if (dSublatticeCharge(iSPI,2,l2) == 0D0) then
                    ! neutral
                    dgdc1(i) = dgdc1(i) + lc1 * dSiteFraction(iSPI,2,l2) * dStdGibbsEnergy(j)
                else
                    ! cation / anion
                    if (i == l1) dgdc1(i) = dgdc1(i) + dSiteFraction(iSPI,2,l2) * dStdGibbsEnergy(j)
                end if

            end do

            ! Entropy
            dgdc1(i) = dgdc1(i) + (1 + DLOG(dSiteFraction(iSPI,1,i))) * p
            do j = 1, nConstituentSublattice(iSPI,1)
                dgdc1(i) = dgdc1(i) + dSublatticeCharge(iSPI,1,i) * yva &
                                    * dSiteFraction(iSPI,1,j)*DLOG(dSiteFraction(iSPI,1,j))
            end do
            do j = 1, nConstituentSublattice(iSPI,2)
                dgdc1(i) = dgdc1(i) + dSublatticeCharge(iSPI,1,i) * dSiteFraction(iSPI,2,j) * DLOG(dSiteFraction(iSPI,2,j))
            end do
        end do

        ! For Sublattice Number 2
        do i = 1, nConstituentSublattice(iSPI,2)
            do j = iFirst, iLast
                ! Relative species index:
                n = j - iFirst + 1

                ! Store constituent indices:
                l1 = iConstituentSublattice(iSPI,1,n)
                l2 = iConstituentSublattice(iSPI,2,n)

                if (cConstituentNameSUB(iSPI,2,l2) == 'Va') then
                    ! cation / vacancy
                    if (i == l2) dgdc2(i) = dgdc2(i) + q * dSiteFraction(iSPI,1,l1) * dStdGibbsEnergy(j)
                else if (dSublatticeCharge(iSPI,2,l2) == 0D0) then
                    ! neutral
                    if (i == l2) dgdc2(i) = dgdc2(i) + q * dStdGibbsEnergy(j)
                else
                    ! cation / anion
                    if (i == l2) dgdc2(i) = dgdc2(i) + dSiteFraction(iSPI,1,l1) * dStdGibbsEnergy(j)
                end if
            end do
            ! Entropy
            dgdc2(i) = dgdc2(i) + (1 + DLOG(dSiteFraction(iSPI,2,i))) * q
            do j = 1, nConstituentSublattice(iSPI,1)
                if (cConstituentNameSUB(iSPI,2,i) == 'Va') then
                    ! cation / vacancy
                    dgdc2(i) = dgdc2(i) + q * dSiteFraction(iSPI,1,j) * DLOG(dSiteFraction(iSPI,1,j))
                else if (dSublatticeCharge(iSPI,2,j) == 0D0) then
                    ! neutral
                else
                    ! cation / anion
                    dgdc2(i) = dgdc2(i) + (-dSublatticeCharge(iSPI,2,i)) * dSiteFraction(iSPI,1,j) * DLOG(dSiteFraction(iSPI,1,j))
                end if
            end do
        end do
        print*,"After All"
        print*,"dgdc1(:)",dgdc1(:)*dIdealConstant * dTemperature
        print*,"dgdc2(:)",dgdc2(:)*dIdealConstant * dTemperature
        print*,""
        ! Compute the chemical potential for each phase component assuming ideal mixing:
        LOOP_Ideal: do i = iFirst, iLast
            ! Relative species index:
            m = i - iFirst + 1
            k1 = iConstituentSublattice(iSPI,1,m)
            k2 = iConstituentSublattice(iSPI,2,m)

            kc1 = 1D0
            ! cation / vacancy
            if (cConstituentNameSUB(iSPI,2,k2) == 'Va') then
                kc2 = 1D0
                natom = 1D0 / dMol + dMolDerivatives(m) * dMolAtoms
            ! neutral
            else if (dSublatticeCharge(iSPI,2,k2) == 0D0) then
                kc2 = 1D0
                natom = 1D0 / dMol + dMolDerivatives(m) * dMolAtoms
            ! cation / anion
            else
                if (k1 > 0) kc1 = dSublatticeCharge(iSPI,1,k1)
                kc2 = -dSublatticeCharge(iSPI,2,k2)
                natom = (kc1 + kc2) / dMol + dMolDerivatives(m) * dMolAtoms
            end if

            dChemicalPotential(i) = (gref + gideal + gexcess) * natom

            do j = 1, nConstituentSublattice(iSPI,1)
                ! cation / (anion or vacancy)
                if (k1 > 0) then
                    dydn = -kc2 * dSiteFraction(iSPI,1,j) / dSub1Total
                    if (j == k1) dydn = dydn + kc2 / dSub1Total
                    dChemicalPotential(i) = dChemicalPotential(i) + dydn * dgdc1(j) * dMolAtoms / dMol
                end if
            end do

            do j = 1, nConstituentSublattice(iSPI,2)
                dydn = -kc1 * dSiteFraction(iSPI,2,j) / dSub2Total
                if (j == k2) dydn = dydn + kc1 / dSub2Total
                dChemicalPotential(i) = dChemicalPotential(i) + dydn * dgdc2(j) * dMolAtoms / dMol
            end do
        end do LOOP_Ideal

        deallocate(dgdc1,dgdc2)
        deallocate(dMolDerivatives)
        deallocate(iMixType)
    end if IF_SUBL

    return

end subroutine CompExcessGibbsEnergySUBI
