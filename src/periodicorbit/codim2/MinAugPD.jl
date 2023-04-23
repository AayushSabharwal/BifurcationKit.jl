"""
$(SIGNATURES)

For an initial guess from the index of a PD bifurcation point located in ContResult.specialpoint, returns a point which will be refined using `newtonFold`.
"""
function PDPoint(br::AbstractBranchResult, index::Int)
	bptype = br.specialpoint[index].type
	@assert bptype == :pd "This should be a PD point"
	specialpoint = br.specialpoint[index]
	return BorderedArray(_copy(specialpoint.x), specialpoint.param)
end

function applyJacobianPeriodDoubling(pb, x, par, dx, _transpose = false)
	if _transpose == false
		# THIS CASE IS NOT REALLY USED
		# if hasJvp(pb)
		# 	return jvp(pb, x, par, dx)
		# else
		# 	return apply(jacobianPeriodDoubling(pb, x, par), dx)
		# end
		@assert 1==0 "Please report to the website of BifurcationKit"
	else
		# if matrix-free:
		if hasAdjoint(pb)
			return jacobianAdjointPeriodDoublingMatrixFree(pb, x, par, dx)
		else
			return apply(transpose(jacobianPeriodDoubling(pb, x, par)), dx)
		end
	end
end
####################################################################################################
@inline getVec(x, ::PeriodDoublingProblemMinimallyAugmented) = extractVecBLS(x)
@inline getP(x, ::PeriodDoublingProblemMinimallyAugmented) = extractParBLS(x)

pdtest(JacPD, v, w, J22, _zero, n; lsbd = MatrixBLS()) = lsbd(JacPD, v, w, J22, _zero, n)

# this function encodes the functional
function (𝐏𝐝::PeriodDoublingProblemMinimallyAugmented)(x, p::T, params) where T
	# These are the equations of the minimally augmented (MA) formulation of the Period-Doubling bifurcation point
	# input:
	# - x guess for the point at which the jacobian is singular
	# - p guess for the parameter value `<: Real` at which the jacobian is singular
	# The jacobian of the MA problem is solved with a BLS method
	a = 𝐏𝐝.a
	b = 𝐏𝐝.b
	# update parameter
	par = set(params, getLens(𝐏𝐝), p)
	# ┌        ┐┌  ┐   ┌ ┐
	# │ J+I  a ││v │ = │0│
	# │ b    0 ││σ │   │1│
	# └        ┘└  ┘   └ ┘
	# In the notations of Govaerts 2000, a = w, b = v
	# Thus, b should be a null vector of J +I
	#       a should be a null vector of J'+I
	# we solve Jv + v + a σ1 = 0 with <b, v> = 1
	# the solution is v = -σ1 (J+I)\a with σ1 = -1/<b, (J+I)^{-1}a>
	# @debug "" x par
	J = jacobianPeriodDoubling(𝐏𝐝.prob_vf, x, par)
	σ = pdtest(J, a, b, T(0), 𝐏𝐝.zero, T(1); lsbd = 𝐏𝐝.linbdsolver)[2]
	return residual(𝐏𝐝.prob_vf, x, par), σ
end

# this function encodes the functional
function (𝐏𝐝::PeriodDoublingProblemMinimallyAugmented)(x::BorderedArray, params)
	res = 𝐏𝐝(x.u, x.p, params)
	return BorderedArray(res[1], res[2])
end

@views function (𝐏𝐝::PeriodDoublingProblemMinimallyAugmented)(x::AbstractVector, params)
	res = 𝐏𝐝(x[1:end-1], x[end], params)
	return vcat(res[1], res[2])
end

###################################################################################################
# Struct to invert the jacobian of the pd MA problem.
struct PDLinearSolverMinAug <: AbstractLinearSolver; end

function PDMALinearSolver(x, p::T, 𝐏𝐝::PeriodDoublingProblemMinimallyAugmented, par,
							rhsu, rhsp;
							debugArray = nothing) where T
	################################################################################################
	# debugArray is used as a temp to be filled with values used for debugging. If debugArray = nothing, then no debugging mode is entered. If it is AbstractArray, then it is populated
	################################################################################################
	# Recall that the functional we want to solve is [F(x,p), σ(x,p)]
	# where σ(x,p) is computed in the above functions and F is the periodic orbit
	# functional. We recall that N⋅[v, σ] ≡ [0, 1]
	# The Jacobian Jpd of the functional is expressed at (x, p)
	# We solve here Jpd⋅res = rhs := [rhsu, rhsp]
	# The Jacobian expression of the PD problem is
	#           ┌          ┐
	#    Jpd =  │ dxF  dpF │
	#           │ σx   σp  │
	#           └          ┘
	# where σx := ∂_xσ and σp := ∂_pσ
	# We recall the expression of
	#			σx = -< w, d2F(x,p)[v, x2]>
	# where (w, σ2) is solution of J'w + b σ2 = 0 with <a, w> = n
	########################## Extraction of function names ########################################
	a = 𝐏𝐝.a
	b = 𝐏𝐝.b

	# get the PO functional, ie a WrapPOSh, WrapPOTrap, WrapPOColl
	POWrap = 𝐏𝐝.prob_vf

	# parameter axis
	lens = getLens(𝐏𝐝)
	# update parameter
	par0 = set(par, lens, p)

	# we define the following jacobian. It is used at least 3 times below. This avoids doing 3 times the (possibly) costly building of J(x, p)
	JPD = jacobianPeriodDoubling(POWrap, x, par0) # jacobian with period doubling boundary condition

	# we do the following in order to avoid computing the jacobian twice in case 𝐏𝐝.Jadjoint is not provided
	JPD★ = hasAdjoint(𝐏𝐝) ? jacobianAdjointPeriodDoubling(POWrap, x, par0) : transpose(JPD)

	# we solve N[v, σ1] = [0, 1]
	v, σ1, cv, itv = pdtest(JPD, a, b, T(0), 𝐏𝐝.zero, T(1); lsbd = 𝐏𝐝.linbdsolver)
	~cv && @debug "Linear solver for N did not converge."

	# # we solve Nᵗ[w, σ2] = [0, 1]
	w, σ2, cv, itw = pdtest(JPD★, b, a, T(0), 𝐏𝐝.zero, T(1); lsbd = 𝐏𝐝.linbdsolver)
	~cv && @debug "Linear solver for Nᵗ did not converge."

	δ = getDelta(POWrap)
	ϵ1, ϵ2, ϵ3 = T(δ), T(δ), T(δ)
	################### computation of σx σp ####################
	################### and inversion of Jpd ####################
	dₚF = minus(residual(POWrap, x, set(par, lens, p + ϵ1)),
				residual(POWrap, x, set(par, lens, p - ϵ1))); rmul!(dₚF, T(1 / (2ϵ1)))
	dJvdp = minus(apply(jacobianPeriodDoubling(POWrap, x, set(par, lens, p + ϵ3)), v),
				  apply(jacobianPeriodDoubling(POWrap, x, set(par, lens, p - ϵ3)), v));
	rmul!(dJvdp, T(1/(2ϵ3)))
	σₚ = -dot(w, dJvdp)

	if hasHessian(𝐏𝐝) == false || 𝐏𝐝.usehessian == false
		# We invert the jacobian of the PD problem when the Hessian of x -> F(x, p) is not known analytically.
		# apply Jacobian adjoint
		u1 = applyJacobianPeriodDoubling(POWrap, x .+ ϵ2 .* vcat(v,0), par0, w, true)
		u2 = apply(JPD★, w) #TODO this has been already computed !!!
		σₓ = minus(u2, u1); rmul!(σₓ, 1 / ϵ2)

		# a bit of a Hack
		xtmp = copy(x); xtmp[end] += ϵ1
		σₜ = (𝐏𝐝(xtmp, p, par0)[end] - 𝐏𝐝(x, p, par0)[end]) / ϵ1
		########## Resolution of the bordered linear system ########
		# we invert Jpd
		_Jpo = jacobian(POWrap, x, par0)
		dX, dsig, flag, it = 𝐏𝐝.linbdsolver(_Jpo, dₚF, vcat(σₓ, σₜ), σₚ, rhsu, rhsp)
		~flag && @debug "Linear solver for J did not converge."

		# Jfd = finiteDifferences(z->𝐏𝐝(z,par0),vcat(x,p))
		# _Jpo = jacobian(POWrap, x, par0).jacpb |> copy
		# Jana = [_Jpo dₚF ; vcat(σₓ,σₜ)' σₚ]
		#
		# # @debug "" size(σₓ) σₚ size(dₚF) size(_Jpo)
		# @infiltrate

		~flag && @debug "Linear solver for J did not converge."
	else
		@assert 1==0 "WIP"
	end

	if debugArray isa AbstractArray
		debugArray .= [jacobian(POWrap, x, par0) dₚF ; σₓ' σₚ]
	end

	return dX, dsig, true, sum(it) + sum(itv) + sum(itw)
end

function (pdls::PDLinearSolverMinAug)(Jpd, rhs::BorderedArray{vectype, T}; debugArray = nothing, kwargs...) where {vectype, T}
	# kwargs is used by AbstractLinearSolver
	out = PDMALinearSolver((Jpd.x).u,
				 (Jpd.x).p,
				 Jpd.prob,
				 Jpd.params,
				 rhs.u, rhs.p;
				 debugArray = debugArray)
	# this type annotation enforces type stability
	return BorderedArray{vectype, T}(out[1], out[2]), out[3], out[4]
end
###################################################################################################
@inline hasAdjoint(pdpb::PDMAProblem) = hasAdjoint(pdpb.prob)
@inline isSymmetric(pdpb::PDMAProblem) = isSymmetric(pdpb.prob)
residual(pdpb::PDMAProblem, x, p) = pdpb.prob(x, p)

jacobian(pdpb::PDMAProblem{Tprob, Nothing, Tu0, Tp, Tl, Tplot, Trecord}, x, p) where {Tprob, Tu0, Tp, Tl <: Union{Lens, Nothing}, Tplot, Trecord} = (x = x, params = p, prob = pdpb.prob)

jacobian(pdpb::PDMAProblem{Tprob, AutoDiff, Tu0, Tp, Tl, Tplot, Trecord}, x, p) where {Tprob, Tu0, Tp, Tl <: Union{Lens, Nothing}, Tplot, Trecord} = ForwardDiff.jacobian(z -> pdpb.prob(z, p), x)

################################################################################################### Newton / Continuation functions
###################################################################################################
function continuationPD(prob, alg::AbstractContinuationAlgorithm,
				pdpointguess::BorderedArray{vectype, T}, par,
				lens1::Lens, lens2::Lens,
				eigenvec, eigenvec_ad,
				options_cont::ContinuationPar ;
				normC = norm,
				updateMinAugEveryStep = 0,
				bdlinsolver::AbstractBorderedLinearSolver = MatrixBLS(),
				jacobian_ma::Symbol = :autodiff,
			 	computeEigenElements = false,
				kind = PDCont(),
				usehessian = true,
				kwargs...) where {T, vectype}
	@assert lens1 != lens2 "Please choose 2 different parameters. You only passed $lens1"
	@assert lens1 == getLens(prob)

	# options for the Newton Solver inheritated from the ones the user provided
	options_newton = options_cont.newtonOptions

	𝐏𝐝 = PeriodDoublingProblemMinimallyAugmented(
			prob,
			_copy(eigenvec),
			_copy(eigenvec_ad),
			options_newton.linsolver,
			# do not change linear solver if user provides it
			@set bdlinsolver.solver = (isnothing(bdlinsolver.solver) ? options_newton.linsolver : bdlinsolver.solver);
			usehessian = usehessian)

	@assert jacobian_ma in (:autodiff, :minaug)

	# Jacobian for the PD problem
	if jacobian_ma == :autodiff
		pdpointguess = vcat(pdpointguess.u, pdpointguess.p)
		prob_f = PDMAProblem(𝐏𝐝, AutoDiff(), pdpointguess, par, lens2, plotDefault, prob.recordFromSolution)
		opt_pd_cont = @set options_cont.newtonOptions.linsolver = DefaultLS()
	else
		prob_f = PDMAProblem(𝐏𝐝, nothing, pdpointguess, par, lens2, plotDefault, prob.recordFromSolution)
		opt_pd_cont = @set options_cont.newtonOptions.linsolver = PDLinearSolverMinAug()
	end

	# this functions allows to tackle the case where the two parameters have the same name
	lenses = getLensSymbol(lens1, lens2)

	# global variables to save call back
	𝐏𝐝.CP = one(T)
	𝐏𝐝.GPD = one(T)

	# this function is used as a Finalizer
	# it is called to update the Minimally Augmented problem
	# by updating the vectors a, b
	function updateMinAugPD(z, tau, step, contResult; kUP...)
		# user-passed finalizer
		finaliseUser = get(kwargs, :finaliseSolution, nothing)

		# we first check that the continuation step was successful
		# if not, we do not update the problem with bad information!
		success = get(kUP, :state, nothing).converged
		if (~modCounter(step, updateMinAugEveryStep) || success == false)
			return isnothing(finaliseUser) ? true : finaliseUser(z, tau, step, contResult; prob = 𝐇, kUP...)
		end

		x = getVec(z.u)	# PD point
		p1 = getP(z.u)	# first parameter
		p2 = z.p		# second parameter
		newpar = set(par, lens1, p1)
		newpar = set(newpar, lens2, p2)

		a = 𝐏𝐝.a
		b = 𝐏𝐝.b

		POWrap = 𝐏𝐝.prob_vf
		JPD = jacobianPeriodDoubling(POWrap, x, newpar) # jacobian with period doubling boundary condition

		# we do the following in order to avoid computing JPO_at_xp twice in case 𝐏𝐝.Jadjoint is not provided
		JPD★ = hasAdjoint(𝐏𝐝) ? jad(POWrap, x, newpar) : transpose(JPD)

		# normalization
		n = T(1)

		# we solve N[v, σ1] = [0, 1]
		newb, σ1, cv, itv = pdtest(JPD, a, b, T(0), 𝐏𝐝.zero, n)
		~cv && @debug "Linear solver for N did not converge."

		# # we solve Nᵗ[w, σ2] = [0, 1]
		newa, σ2, cv, itw = pdtest(JPD★, b, a, T(0), 𝐏𝐝.zero, n)
		~cv && @debug "Linear solver for Nᵗ did not converge."
		@debug size(JPD★.jacpb) size(w)

		copyto!(𝐏𝐝.a, newa); rmul!(𝐏𝐝.a, 1/normC(newa))
		# do not normalize with dot(newb, 𝐏𝐝.a), it prevents from BT detection
		copyto!(𝐏𝐝.b, newb); rmul!(𝐏𝐝.b, 1/normC(newb))
		@info "Update MinAugPD"
		return true
	end

	function testForGPD_CP(iter, state)
		z = getx(state)
		x = getVec(z)		# pd point
		p1 = getP(z)		# first parameter
		p2 = getp(state)	# second parameter
		newpar = set(par, lens1, p1)
		newpar = set(newpar, lens2, p2)

		prob_pd = iter.prob.prob
		pbwrap = prob_pd.prob_vf

		a = prob_pd.a
		b = prob_pd.b

		# expression of the jacobian
		JPD = jacobianPeriodDoubling(pbwrap, x, newpar) # jacobian with period doubling boundary condition

		# we do the following in order to avoid computing JPO_at_xp twice in case 𝐏𝐝.Jadjoint is not provided
		JPD★ = hasAdjoint(𝐏𝐝) ? jad(pbwrap, x, newpar) : transpose(JPD)

		# compute new b
		n = T(1)
		ζ = pdtest(JPD, a, b, T(0), 𝐏𝐝.zero, n)[1]
		ζ ./= norm(ζ)

		# compute new a
		ζ★ = pdtest(JPD★, b, a, T(0), 𝐏𝐝.zero, n)[1]
		ζ★ ./= norm(ζ★)
		#############
		pd0 = PeriodDoubling(copy(x), p1, newpar, lens1, nothing, nothing, nothing, :none)
		if pbwrap.prob isa ShootingProblem
			pd = perioddoublingNormalForm(pbwrap, pd0, (1, 1), NewtonPar(options_newton, verbose = false); verbose = false)
			prob_pd.GPD = pd.nf.nf.b3
			#############
		end
		if pbwrap.prob isa PeriodicOrbitOCollProblem
			pd = perioddoublingNormalForm(pbwrap, pd0; verbose = false)
			prob_pd.GPD = pd.nf.nf.b3
		end

		return prob_pd.GPD, prob_pd.CP
	end

	# the following allows to append information specific to the codim 2 continuation to the user data
	_printsol = get(kwargs, :recordFromSolution, nothing)
	_printsol2 = isnothing(_printsol) ?
		(u, p; kw...) -> (; zip(lenses, (getP(u), p))..., CP = 𝐏𝐝.CP, GPD = 𝐏𝐝.GPD, namedprintsol(recordFromSolution(prob)(getVec(u), p; kw...))...) :
		(u, p; kw...) -> (; namedprintsol(_printsol(getVec(u), p; kw...))..., zip(lenses, (getP(u, 𝐏𝐝), p))..., CP = 𝐏𝐝.CP, GPD = 𝐏𝐝.GPD	,)

	# eigen solver
	eigsolver = FoldEig(getsolver(opt_pd_cont.newtonOptions.eigsolver))

	prob_f = reMake(prob_f, recordFromSolution = _printsol2)

	event = ContinuousEvent(2, testForGPD_CP, computeEigenElements, ("gpd", "cusp"), 0)

	# solve the P equations
	br_pd_po = continuation(
		prob_f, alg,
		(@set opt_pd_cont.newtonOptions.eigsolver = eigsolver);
		linearAlgo = BorderingBLS(solver = opt_pd_cont.newtonOptions.linsolver, checkPrecision = false),
		kwargs...,
		kind = kind,
		normC = normC,
		event = event,
		finaliseSolution = updateMinAugPD,
		)
	correctBifurcation(br_pd_po)
end
