module module_mp_simple
	implicit none
    real, parameter :: LH_vapor=2.26E6 ! J/kg
	real, parameter :: LH_liquid=3.34E5 ! J/kg
    real, parameter :: heat_capacity = 1021.0 ! air heat capacity J/kg/K
	real, parameter :: SMALL_VALUE = 1E-15
!     real, parameter :: mp_R=287.058 ! J/(kg K) specific gas constant for air
!     real, parameter :: mp_g=9.81 ! gravity m/s^2
	
	contains
	real function sat_mr(t,p)
	! Calculate the saturated mixing ratio at a temperature (K), pressure (Pa)
		implicit none
		real,intent(in) :: t,p
		real :: e_s,mr_s,a,b

! 		from http://www.dtic.mil/dtic/tr/fulltext/u2/778316.pdf
! 			Lowe, P.R. and J.M. Ficke., 1974: THE COMPUTATION OF SATURATION VAPOR PRESSURE 
! 				Environmental Prediction Research Facility, Technical Paper No. 4-74
!		which references:
! 			Murray, F. W., 1967: On the computation of saturation vapor pressure. 
! 				Journal of Applied Meteorology, Vol. 6, pp. 203-204.
! 		Also notes a 6th order polynomial and look up table as viable options. 
		if (t<273.15) then
			a=21.8745584
			b=7.66
		else
			a=17.2693882
			b=35.86
		endif
		e_s = 610.78* exp(a*(T-273.16)/(T-b)) !(Pa)

!		alternate formulations
!		Polynomial:
! 		e_s = ao + t*(a1+t*(a2+t*(a3+t*(a4+t*(a5+a6*t))))) a0-6 defined separately for water and ice
! 		e_s = 611.2*exp(17.67*(t-273.15)/(t-29.65)) ! (Pa)
		!from : http://www.srh.noaa.gov/images/epz/wxcalc/vaporPressure.pdf
! 		e_s = 611.0*10.0**(7.5*(t-273.15)/(t-35.45))
		
		
		!from : http://www.srh.noaa.gov/images/epz/wxcalc/mixingRatio.pdf
		sat_mr=0.62197*e_s/(p-e_s) !(kg/kg)
	end function sat_mr
	
	subroutine cloud_conversion(p,t,qv,qc,qvsat,dt)
		implicit none
		real,intent(inout)::t,qv,qc,qvsat
		real,intent(in)::dt,p
		real :: vapor2temp,excess,deltat
		vapor2temp=LH_vapor/heat_capacity
		
! 		calculate the saturating mixing ratio
		qvsat=sat_mr(t,p)
! 		if saturated create clouds
		if (qv>qvsat) then
			excess=qv-qvsat
! 			temperature change if all vapor is converted
			deltat=excess*vapor2temp
! 			Now calculate new saturated mixing ratio at the new hypothetical tempera
			qvsat=sat_mr(t+deltat*0.5,p)
			excess=qv-qvsat
			t=t+(excess*vapor2temp)
			qv=qv-excess
			qc=qc+excess
			
! 		if unsaturated anc clouds exist, evaporate clouds
		else if (qc>0) then
			excess=qvsat-qv
			if (excess<qc) then
				deltat=excess*vapor2temp
				qvsat=sat_mr(t-deltat*0.5,p)
				excess=qvsat-qv
				if (excess<qc) then
					t=t-(excess*vapor2temp)
					qv=qv+excess
					qc=qc-excess
				else
					qv=qv+qc
					t=t-(qc*vapor2temp)
					qc=0.
				endif
			else
				qv=qv+qc
				t=t-(qc*vapor2temp)
				qc=0.
			endif
		endif
		qc=max(qc,0.)
	end subroutine

	subroutine cloud2hydrometeor(qc,q,conversion)
		implicit none
		real,intent(inout) :: qc,q
		real,intent(in) :: conversion
		real::delta
		
		delta=qc*conversion
! 		if (delta>0) then
! 			print*,"Converting to hydrometeor!", delta
! 		else
! 			print*, " no conversion???",qc,conversion
! 		endif
		if (delta<qc) then
			qc=qc-delta
			q=q+delta
		else
			q=q+qc
			qc=0.
		endif
		qc=max(qc,0.)
	end subroutine
	
	subroutine phase_change(p,t,q1,qmax,q2,Lheat,change_rate)
		implicit none
		real, intent(inout)::t,q1,q2
		real,intent(in) :: p,qmax,change_rate,Lheat
		real :: mass2temp,delta
		mass2temp=Lheat/heat_capacity!*(p/(R*t)*dV))
		
		if (q1>SMALL_VALUE) then
			delta=q1*change_rate
			!make sure we don't over saturate the air
			if (delta>(qmax-q2)) then
				delta=qmax-q2
			endif
			q1=q1-delta
			q2=q2+delta
		else
			delta=q1
			if (delta>(qmax-q2)) then
				delta=qmax-q2
			endif
			q2=q2+delta
			q1=0.
		endif
		t=t+delta*mass2temp
	
	end subroutine
	
	subroutine mp_conversions(p,t,qv,qc,qr,qs,dt)
		implicit none
		real, intent(inout) :: p,t,qv,qc,qr,qs
		real,intent(in)::dt
		real :: qvsat,rain_evap_time,snow_evap_time,cloud2rain_time,&
				cloud2snow_time,snow_melt_time,&
				L_evap,L_subl,L_melt
		
		L_melt=LH_liquid !kJ/kg
		L_evap=LH_vapor !kJ/kg
		L_subl=L_melt+L_evap
		!arbitrary calibratable timescales
! 		rain_evap_time=100.0 !seconds
! 		snow_evap_time=200.0 !seconds
! 		snow_melt_time=100.0 !seconds
		cloud2rain_time=500.0!seconds
		cloud2snow_time=2000.0!seconds
		
		!convert cloud water to and from water vapor
		call cloud_conversion(p,t,qv,qc,qvsat,dt)
		! if there are no species to process we will just return
		if ((qc+qr+qs) >SMALL_VALUE) then
			if (qc>SMALL_VALUE) then
				if (t>273.15) then
					! convert cloud water to rain drops
					call cloud2hydrometeor(qc,qr,dt/cloud2rain_time)
! 					if (qs>SMALL_VALUE) then
! 						! it is above freezing, so start melting any snow if present
! 						call phase_change(p,t,qs,100.,qr,L_melt,dt/snow_melt_time)
! ! 						write(*,*) "Snow Melt",t
! 					endif
				else
					! convert cloud water to snow flakes
					call cloud2hydrometeor(qc,qs,dt/cloud2snow_time)
					
				endif
			endif
			! if unsaturated, evaporate any existing snow and rain
! 			if (qv<qvsat) then
! 				if (qr>SMALL_VALUE) then
! 					! evaporate rain
! 					call phase_change(p,t,qr,qvsat,qv,L_evap,dt/rain_evap_time)
! ! 					write(*,*) "evap rain"
! 				endif
! 				if (qs>SMALL_VALUE) then
! 					! sublimate snow
! 					call phase_change(p,t,qs,qvsat,qv,L_subl,dt/snow_evap_time)
! ! 					write(*,*) "evap snow"
! 				endif
! 			endif
		endif
	end subroutine
	
	real function sediment(q,v,rho,dz,n)
		implicit none
		real,intent(inout),dimension(n)::q
		real,intent(in),dimension(n)::v,rho,dz
		integer,intent(in) :: n
		real,dimension(n) :: flux
		integer :: i
		
! 	    calculate the mass of material falling out of the bottom model level
		sediment=v(1)*q(1)*rho(1) ![m] * [kg/kg] * [kg/m^3] = [kg/m^2]
! 		remove that from the bottom model layer. 
		q(1)=q(1)-(sediment/dz(1)/rho(1)) ! [kg/m^2] / [m] / [kg/m^3] = [kg/kg]
		
		do i=1,n-1
			flux(i)=v(i+1)*q(i+1)*rho(i+1)
		enddo
		do i=1,n-1
			q(i)=q(i)+flux(i)/(rho(i)*dz(i))
			q(i+1)=q(i+1)-flux(i)/(rho(i+1)*dz(i+1))
		enddo
	
	end function

	subroutine mp_simple(p,t,rho,qv,qc,qr,qs,rain,snow,dt,dz,nz,debug)
		implicit none
		real,intent(inout),dimension(nz)::p,t,rho,qv,qc,qr,qs
		real,intent(inout)::rain,snow
		real,intent(in),dimension(nz)::dz
		real,intent(in)::dt
		integer,intent(in)::nz
		logical,intent(in)::debug
		real,dimension(nz)::fall_rate
		real::cfl,temp
		integer::i
		
! 		fall_rate=2+(t-260)/5
! 		where(fall_rate>10) fall_rate=10
! 		where(fall_rate<1.5) fall_rate=1.5
		do i=1,nz
			call mp_conversions(p(i),t(i),qv(i),qc(i),qr(i),qs(i),dt)
		enddo

! SEDIMENTATION		
		if (maxval(qr)>SMALL_VALUE) then
			fall_rate=10.0
			cfl=ceiling(maxval(dt/dz*fall_rate))
			fall_rate=dt*fall_rate/cfl
! 			substepping to satisfy CFL criteria
			do i=1,nint(cfl)
				rain=rain+sediment(qr,fall_rate,rho,dz,nz)
			enddo
		endif
		if (maxval(qs)>SMALL_VALUE) then
			fall_rate=1.5
			cfl=ceiling(maxval(dt/dz*fall_rate))
			fall_rate=dt*fall_rate/cfl
! 			substepping to satisfy CFL criteria
			do i=1,nint(cfl)
				temp=sediment(qs,fall_rate,rho,dz,nz)
				snow=snow+temp
				if ((qs(1).lt.0)) then
					write(*,*) qs(1)
				endif
				if ((fall_rate(1).lt.0)) then
					write(*,*) fall_rate(1)
				endif
				if ((rho(1).lt.0)) then
					write(*,*) rho(1)
				endif
				if (temp.lt.0) then
					write(*,*) temp,qs(1),fall_rate(1),rho(1)
				endif
			enddo
		endif
		
	end subroutine mp_simple


	subroutine mp_simple_driver(p,th,pii,rho,qv,qc,qr,qs,rain,snow,dt,dz,nx,ny,nz)
		implicit none
		real,intent(inout),dimension(nx,nz,ny)::p,th,pii,rho,qv,qc,qs,qr,dz
		real,intent(inout),dimension(nx,ny)::rain,snow
		real,intent(in)::dt
		integer,intent(in)::nx,ny,nz
		real,dimension(nz)::t
		integer::i,j
		
! 		print*, nx,nz,ny,dt
		!$omp parallel private(i,j,t),&
		!$omp shared(p,th,pii,qv,qc,qs,qr,rain,snow,dz),&
		!$omp firstprivate(dt,nx,ny,nz)
		!$omp do
        do j=2,ny-1
	        do i=2,nx-1
				t=th(i,:,j)*pii(i,:,j)
				call mp_simple(p(i,:,j),t,rho(i,:,j),qv(i,:,j),&
							qc(i,:,j),qr(i,:,j),qs(i,:,j),&
							rain(i,j),snow(i,j),&
							dt,dz(i,:,j),nz,((i==(nx/2+20)).and.(j==2)))
				th(i,:,j)=t/pii(i,:,j)
! 				print*, maxval(t)
! 				if (minval(qc(i,:,j))<0) then
! 					print*,i,j,minval(qc(i,:,j)), "cloud"
! 				endif
! 				if (minval(qv(i,:,j))<0) then
! 					print*,i,j,minval(qv(i,:,j)), "vapor"
! 				endif
! 				if (minval(qr(i,:,j))<0) then
! 					print*,i,j,minval(qr(i,:,j)), "rain"
! 				endif
! 				if (minval(qs(i,:,j))<0) then
! 					print*,i,j,minval(qs(i,:,j)), "snow"
! 				endif
				
			enddo
		enddo
		!$omp end do
		!$omp end parallel
	end subroutine mp_simple_driver
end module

!!!! "unit" Test Code (sort of)
! program main
! 	use module_mp_simple
! 	real,dimension(5) ::p,t,qv,qc,qr,qs,dz
! 	real::rain,snow,dt,dx2
! 	integer::nz,i
! 	nz=5
! 	p(:)=80000.0
! 	t(:)=270.0
! 	qv(:)=0.005
! 	qc(:)=0.
! 	qr(:)=0.
! 	qs(:)=0.
! 	dz(:)=200.0
! 	dx2=2000*2000.0
! 	dt=20.0
! 	rain=0
! 	snow=0
! 	
! 	do i=1,10
! 		call mp_simple(p,t,qv,qc,qr,qs,rain,snow,dt,dx2,dz,nz)
! ! 		write(*,*) "p=",p
! 		write(*,*) t(2),qv(2),qc(2),qr(2),qs(2),rain,snow
! ! 		write(*,*) "t=",t
! ! 		write(*,*) "qv=",qv
! ! 		write(*,*) "qc=",qc
! ! 		write(*,*) "qr=",qr
! ! 		write(*,*) "qs=",qs
! ! 		write(*,*) "rain=",rain
! ! 		write(*,*) "snow=",snow
! 	end do
! end program
	
