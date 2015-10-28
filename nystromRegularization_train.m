function [ output ] = nystromRegularization_train( X , Y , varargin )
%     nystromRegularization Nystrom computational regularization - Early Stopping cross validation
%       Performs selection of the Nystrom regularization parameter
%       (subsampling level m)
%       in the context of Nystrom low-rank kernel approximation
%     
%       INPUT
%       =====
%     
%       X : Input samples
%     
%       Y : Output signals
%     
%       config.  \\ optional configuration structure. See config_set.m for
%                \\ default values
%     
%              data.
%                   shuffle : 1/0 flag - Shuffle the training indexes
%     
%              crossValidation.
%                              storeTrainingError : 1/0 - Store training error
%                                                   flag
%     
%                              validationPart : in (0,1) - Fraction of the
%                                               training set used for validation
%     
%                              recompute : 1/0 flag - Recompute solution using the
%                                          whole training set after cross validation
%     
%                              errorFunction : handle to the function used for
%                                              error computation
%     
%                              codingFunction : handle to the function used for
%                                               coding (in classification tasks)
%     
%                              stoppingRule : handle to the stopping rule function
%     
%                              windowSize : Size of the window used by the
%                                           stopping rule (default = 10)
%     
%                              threshold : Threshold used by the
%                                          stopping rule (default = 0)
%     
%              filter.
%                     lambdaGuesses : Vector of guesses for the Tikhonov
%                     regularization parameter
%     
%              kernel.
%                     kernelFunction : handle to the kernel function
%     
%                     kernelParameter : vector of size r. r is the number of
%                                        parameters required by kernelFunction.
%     
%                     fixedM : Integer - fixed Nystrom subsampling level
%                     (no crossvalidation)
%
%                     minM : Integer - Minimum Nystrom subsampling level
%
%                     maxM : Integer - Maximium Nystrom subsampling level
%
%                     numStepsM : Integer - Number of Nystrom subsampling
%                     level guesses (iterative steps)
%     
%       OUTPUT
%       ======
%     
%       output.
%     
%              best.
%                   validationError
%                   m
%                   alpha
%                   lambda
%                   lambdaIdx
%     
%              nysIdx : Vector - selected Nystrom approximation indexes
%     
%              time.
%                   kernelComputation
%                   crossValidationTrain
%                   crossValidationEval
%                   crossValidationTotal
%     
%              errorPath.
%                        training
%                        validation

    % Check config struct
    if nargin >2
        config = varargin{1};
    else
        config = config_set();  % Construct default configuration structure
    end

    ntr = size(Y,1);
    t = size(Y,2);  % number of output signals

    % Best parameters variables init
    output.best = struct();
%     output.best.alpha = zeros(config.kernel.m,t);

    if isempty(config.filter.fixedM) && isempty(config.filter.numStepsM)

        error('Specify either a fixed or a number of steps for the subsampling level m')

    elseif isempty(config.filter.fixedM) && ~isempty(config.filter.numStepsM) 
        
        config.kernel.mGuesses = round(linspace(config.kernel.minM, config.kernel.maxM , config.kernel.numStepsM));

        %%% Perform cross validation

        output.best.validationError = Inf;
        output.best.m = config.kernel.maxM;

        % Error buffers
        output.errorPath.validation = zeros(1,config.kernel.numStepsM) * NaN;
        if config.crossValidation.storeTrainingError == 1
            output.errorPath.training = zeros(1,config.kernel.numStepsM) * NaN;
        else
            output.errorPath.training = [];
        end

        % Init time structures
        output.time.kernelComputation = 0;
        output.time.crossValidationTrain = 0;
        output.time.crossValidationEval = 0;

        % Subdivide training set in training1 and validation

        ntr1 = floor( ntr * ( 1 - config.crossValidation.validationPart ));

        if config.data.shuffle == 1

            shuffledIdx = randperm(ntr);
            trainIdx = shuffledIdx(1 : ntr1);
            valIdx = shuffledIdx(ntr1 + 1 : end);

        else

            trainIdx = 1 : ntr1;
            valIdx = ntr1 + 1 : ntr;

        end

        Xtr1 = X(trainIdx,:);
        Ytr1 = Y(trainIdx,:);
        Xval = X(valIdx,:);
        Yval = Y(valIdx,:);

        for i = 1:config.filter.numLambdaGuesses
            
            l = config.filter.lambdaGuesses(i);

            for j = 1:config.kernel.numStepsM

                m = config.kernel.mGuesses(j);
                
                if storeFullTrainTime == 1
                    tic
                end

                %%%%%%%%%%%%%%%%%%%%%%%%%%%
                % Incremental Update Rule %
                %%%%%%%%%%%%%%%%%%%%%%%%%%%

                if j == 1

                    %%% Initialization (j = 1)

                    % Preallocate matrices
                    A = zeros(ntr1 , config.kernel.maxM);
                    Aty = zeros(config.kernel.maxM , t);

                    R = cell(size(config.filter.lambdaGuesses));
                    [R{:,:}] = deal(zeros(config.kernel.maxM));

                    alpha = cell(size(config.filter.lambdaGuesses));
                    [alpha{:,:}] = deal(zeros(config.kernel.maxM,t));

                    % Sample columns and compute
                    samp = 1:m;
                    Xs = Xtr1(samp,:);
                    
                    tic
                    SqDistMat = computeSqDistMat(Xtr1 , Xs);
                    A(:,samp) = exp( - SqDistMat / (2 * config.kernel.kernelParameter^2) );
                    B = A(samp,samp);
                    output.time.kernelComputation = output.time.kernelComputation + toc;
                    
                    tic
                    Aty(samp,:) = A(:,samp)' * Ytr1;

                    R{i}(1:m,1:m) = ...
                        chol(full(A(:,1:m)' * A(:,1:m) ) + ...
                        ntr1 * l * B);

                    % alpha
                    alpha{i} = 	R{i}(1:m,1:m) \ ...
                        ( R{i}(1:m,1:m)' \ ...
                        ( Aty(1:m,:) ) );

                    output.time.crossValidationTrain = output.time.crossValidationTrain + toc;
                    
                else

                    %%% Generic j-th incremental update step (j > 1)
                    
                    mPrev = config.kernel.mGuesses(j - 1);
                    
                    % Sample new columns of K
                    samp = (mPrev + 1) : m;
                    XsNew = Xtr1(samp,:);
                    Xs = [Xs ; XsNew];
                    
                    % Computer a, b, beta
                    tic
                    SqDistMat = computeSqDistMat(Xtr1 , XsNew);
                    a = exp( - SqDistMat / (2 * config.kernel.kernelParameter^2) ) ;
                    output.time.kernelComputation = output.time.kernelComputation + toc;
                    
                    b = a( 1:mPrev , : );
                    beta = a( samp , : );

                    tic
                    % Compute c, gamma
                    c = A(:,1:mPrev)' * a + ntr1 * filterParGuesses(k) * b;
                    gamma = a' * a + ntr1 * filterParGuesses(k) * beta;

                    % Update A, Aty
                    A( : , (mPrev+1) : m ) = a ;
                    Aty( (mPrev+1) : m , : ) = a' * Ytr1 ;

                    % Compute u, v
                    u = [ c / ( 1 + sqrt( 1 + gamma) ) ; ...
                                    sqrt( 1 + gamma) ];

                    v = [ c / ( 1 + sqrt( 1 + gamma) ) ; ...
                                    -1               ];

                    % Update R
                    R{i}(1:m,1:m) = ...
                        cholupdatek( R{i}(1:m,1:m) , u , '+');

                    R{i}(1:m,1:m) = ...
                        cholupdatek(R{i}(1:m,1:m) , v , '-');

                    % Recompute alpha
                    alpha{i} = 	R{i}(1:m,1:m) \ ...
                        ( R{i}(1:m,1:m)' \ ...
                        ( Aty(1:m,:) ) );

                    output.time.crossValidationTrain = output.time.crossValidationTrain + toc;

                end
                
                % Evaluate validation error and select model
                
                % Initialize TrainVal kernel       
                tic
                Kval = config.kernel.kernelFunction(Xval, Xs);

                % Compute validation predictions matrix
                YvalPred = Kval * alpha{k};

                % Compute validation performance
                if ~isempty(config.crossValidation.codingFunction)
                    YvalPred = config.crossValidation.codingFunction(YvalPred);
                end
                output.errorPath.validation(i,j) = config.crossValidation.errorFunction(Yval , YvalPred);
                output.time.crossValidationEval = output.time.crossValidationEval + toc;

                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                %  Store performance matrices  %
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

                if config.crossValidation.storeTrainingError == 1                    

                    % Compute training predictions matrix
                    YtrainPred = A * alpha{i};

                    % Compute training performance
                    if ~isempty(config.crossValidation.codingFunction)
                        YtrainPred = config.crossValidation.codingFunction(YtrainPred);
                    end
                    output.errorPath.training(i,j) = config.crossValidation.errorFunction(Ytr1 , YtrainPred);                    
                end

                %%%%%%%%%%%%%%%%%%%%
                % Store best model %
                %%%%%%%%%%%%%%%%%%%%
                if output.errorPath.validation(i,j) < valM

                    %Update best filter parameter
                    output.best.lambda = lambdaGuesses(i);
                    output.best.lambdaIdx = i;

                    %Update best validation performance measurement
                    output.best.validationError = output.errorPath.validation(i,j);

                    % Update internal model samples matrix
                    output.best.sampledPoints = Xs;

                    % Update coefficients vector
                    output.best.alpha = alpha{i};
                end
                
                output.time.crossValidationTotal = output.time.crossValidationTrain + output.time.crossValidationEval ;                
            end
        end  

        if config.crossValidation.recompute == 1

            %%% Retrain on whole dataset

            tic
            beta = zeros(config.kernel.m,t);
            if isempty(config.filter.gamma)
                gamma = 1/(norm(Knm/R))^2;
            else
                gamma = config.filter.gamma;
            end

            % Compute solution
            for iter = 1:output.best.iteration
                % Update filter
                beta = beta -  gamma * (R' \ ( Knm' * ( Knm * (R \ beta) - Y ) ) );
            end

            output.best.alpha = R\beta; % Get alpha from beta

            output.time.fullTraining = toc;
        end


    elseif ~isempty(config.filter.fixedIterations)

        %%% Just train
        
%         % Initialize Train kernel
% 
%         % Subsample training examples for Nystrom approximation
%         nysIdx = randperm(ntr , config.kernel.m);
%         output.nysIdx = nysIdx;
% 
%         % Compute kernels
%         tic
%         Knm = config.kernel.kernelFunction(X, X(nysIdx,:), config.kernel.kernelParameters);
%         Kmm = Knm(nysIdx,:);
%         R = chol( ( Kmm + Kmm') / 2 + 1e-10 * eye(config.kernel.m));  % Compute upper Cholesky factor of Kmm    
%         output.time.kernelComputation = toc;
% 
%         tic
%         beta = zeros(config.kernel.m,t);
%         if isempty(config.filter.gamma)
%             gamma = 1/(norm(Knm/R))^2;
%         else
%             gamma = config.filter.gamma;
%         end
% 
%         % Compute solution with a fixed number of steps
%         for iter = 1:config.filter.fixedIterations
%             % Update filter
%             beta = beta -  gamma * (R' \ ( Knm' * ( Knm * (R \ beta) - Y ) ) );
%         end
% 
%         output.best.alpha = R\beta; % Get alpha from beta
% 
%         output.time.fullTraining = toc;
    end

    output.config = config;
end
