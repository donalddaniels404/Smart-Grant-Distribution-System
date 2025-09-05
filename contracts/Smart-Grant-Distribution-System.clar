(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-GRANT (err u101))
(define-constant ERR-ALREADY-INITIALIZED (err u102))
(define-constant ERR-MILESTONE-NOT-FOUND (err u103))
(define-constant ERR-INVALID-AMOUNT (err u104))
(define-constant ERR-MILESTONE-ALREADY-COMPLETED (err u105))

(define-data-var contract-owner principal tx-sender)
(define-data-var total-grants uint u0)

(define-map grants 
    { grant-id: uint }
    {
        recipient: principal,
        total-amount: uint,
        remaining-amount: uint,
        milestone-count: uint,
        status: (string-ascii 20)
    }
)

(define-map milestones
    { grant-id: uint, milestone-id: uint }
    {
        amount: uint,
        description: (string-ascii 100),
        completed: bool,
        approved: bool
    }
)

(define-map validators
    principal 
    bool
)

(define-public (initialize-contract)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok true)
    )
)

(define-public (add-validator (validator principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (map-set validators validator true)
        (ok true)
    )
)

(define-public (create-grant (recipient principal) (total-amount uint) (milestone-count uint))
    (let ((grant-id (+ (var-get total-grants) u1)))
        (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (> milestone-count u0) ERR-INVALID-AMOUNT)
        (map-set grants
            { grant-id: grant-id }
            {
                recipient: recipient,
                total-amount: total-amount,
                remaining-amount: total-amount,
                milestone-count: milestone-count,
                status: "ACTIVE"
            }
        )
        (var-set total-grants grant-id)
        (ok grant-id)
    )
)

(define-public (add-milestone (grant-id uint) (milestone-id uint) (amount uint) (description (string-ascii 100)))
    (let ((grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT)))
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (map-set milestones
            { grant-id: grant-id, milestone-id: milestone-id }
            {
                amount: amount,
                description: description,
                completed: false,
                approved: false
            }
        )
        (ok true)
    )
)

(define-public (submit-milestone (grant-id uint) (milestone-id uint))
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (milestone (unwrap! (get-milestone grant-id milestone-id) ERR-MILESTONE-NOT-FOUND))
    )
        (asserts! (is-eq tx-sender (get recipient grant)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get completed milestone)) ERR-MILESTONE-ALREADY-COMPLETED)
        (map-set milestones
            { grant-id: grant-id, milestone-id: milestone-id }
            (merge milestone { completed: true })
        )
        (ok true)
    )
)

(define-public (approve-milestone (grant-id uint) (milestone-id uint))
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (milestone (unwrap! (get-milestone grant-id milestone-id) ERR-MILESTONE-NOT-FOUND))
    )
        (asserts! (default-to false (map-get? validators tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (get completed milestone) ERR-MILESTONE-NOT-FOUND)
        (asserts! (not (get approved milestone)) ERR-MILESTONE-ALREADY-COMPLETED)
        (try! (stx-transfer? (get amount milestone) tx-sender (get recipient grant)))
        (map-set milestones
            { grant-id: grant-id, milestone-id: milestone-id }
            (merge milestone { approved: true })
        )
        (map-set grants
            { grant-id: grant-id }
            (merge grant { 
                remaining-amount: (- (get remaining-amount grant) (get amount milestone))
            })
        )
        (ok true)
    )
)

(define-read-only (get-grant (grant-id uint))
    (map-get? grants { grant-id: grant-id })
)

(define-read-only (get-milestone (grant-id uint) (milestone-id uint))
    (map-get? milestones { grant-id: grant-id, milestone-id: milestone-id })
)

(define-read-only (is-validator (address principal))
    (default-to false (map-get? validators address))
)

(define-constant ERR-GRANT-EXPIRED (err u106))
(define-constant ERR-INVALID-DEADLINE (err u107))

(define-map grant-deadlines
    { grant-id: uint }
    {
        created-at: uint,
        deadline: uint,
        expired: bool
    }
)

(define-public (create-grant-with-deadline (recipient principal) (total-amount uint) (milestone-count uint) (deadline-blocks uint))
    (let ((grant-id (+ (var-get total-grants) u1))
          (current-block stacks-block-height)
          (deadline (+ current-block deadline-blocks)))
        (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (> milestone-count u0) ERR-INVALID-AMOUNT)
        (asserts! (> deadline-blocks u0) ERR-INVALID-DEADLINE)
        (map-set grants
            { grant-id: grant-id }
            {
                recipient: recipient,
                total-amount: total-amount,
                remaining-amount: total-amount,
                milestone-count: milestone-count,
                status: "ACTIVE"
            }
        )
        (map-set grant-deadlines
            { grant-id: grant-id }
            {
                created-at: current-block,
                deadline: deadline,
                expired: false
            }
        )
        (var-set total-grants grant-id)
        (ok grant-id)
    )
)

(define-public (expire-grant (grant-id uint))
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (deadline-info (unwrap! (get-grant-deadline grant-id) ERR-INVALID-GRANT))
    )
        (asserts! (>= stacks-block-height (get deadline deadline-info)) ERR-INVALID-GRANT)
        (asserts! (not (get expired deadline-info)) ERR-ALREADY-INITIALIZED)
        (map-set grants
            { grant-id: grant-id }
            (merge grant { status: "EXPIRED" })
        )
        (map-set grant-deadlines
            { grant-id: grant-id }
            (merge deadline-info { expired: true })
        )
        (ok true)
    )
)

(define-public (extend-grant-deadline (grant-id uint) (additional-blocks uint))
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (deadline-info (unwrap! (get-grant-deadline grant-id) ERR-INVALID-GRANT))
    )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get expired deadline-info)) ERR-GRANT-EXPIRED)
        (asserts! (> additional-blocks u0) ERR-INVALID-AMOUNT)
        (map-set grant-deadlines
            { grant-id: grant-id }
            (merge deadline-info { 
                deadline: (+ (get deadline deadline-info) additional-blocks)
            })
        )
        (ok true)
    )
)

(define-read-only (get-grant-deadline (grant-id uint))
    (map-get? grant-deadlines { grant-id: grant-id })
)

(define-read-only (is-grant-expired (grant-id uint))
    (match (get-grant-deadline grant-id)
        deadline-info (>= stacks-block-height (get deadline deadline-info))
        false
    )
)

(define-constant ERR-INSUFFICIENT-APPROVALS (err u108))
(define-constant ERR-ALREADY-VOTED (err u109))
(define-constant ERR-INVALID-THRESHOLD (err u110))
(define-constant ERR-REPORT-NOT-FOUND (err u111))
(define-constant ERR-REPORT-ALREADY-SUBMITTED (err u112))

(define-data-var approval-threshold uint u2)

(define-map milestone-approvals
    { grant-id: uint, milestone-id: uint }
    {
        approval-count: uint,
        rejection-count: uint,
        finalized: bool
    }
)

(define-map validator-votes
    { grant-id: uint, milestone-id: uint, validator: principal }
    {
        vote: bool,
        voted: bool
    }
)

(define-map milestone-reports
    { grant-id: uint, milestone-id: uint }
    {
        progress-percentage: uint,
        deliverable-url: (string-ascii 200),
        notes: (string-ascii 500),
        submitted-at: uint,
        submitted: bool
    }
)

(define-public (set-approval-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (> new-threshold u0) ERR-INVALID-THRESHOLD)
        (var-set approval-threshold new-threshold)
        (ok true)
    )
)

(define-public (vote-milestone (grant-id uint) (milestone-id uint) (approve bool))
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (milestone (unwrap! (get-milestone grant-id milestone-id) ERR-MILESTONE-NOT-FOUND))
        (current-approvals (default-to 
            { approval-count: u0, rejection-count: u0, finalized: false }
            (map-get? milestone-approvals { grant-id: grant-id, milestone-id: milestone-id })
        ))
        (existing-vote (map-get? validator-votes { grant-id: grant-id, milestone-id: milestone-id, validator: tx-sender }))
    )
        (asserts! (default-to false (map-get? validators tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (get completed milestone) ERR-MILESTONE-NOT-FOUND)
        (asserts! (not (get finalized current-approvals)) ERR-MILESTONE-ALREADY-COMPLETED)
        (asserts! (is-none existing-vote) ERR-ALREADY-VOTED)
        
        (map-set validator-votes
            { grant-id: grant-id, milestone-id: milestone-id, validator: tx-sender }
            { vote: approve, voted: true }
        )
        
        (let ((new-approvals (if approve
            (merge current-approvals { approval-count: (+ (get approval-count current-approvals) u1) })
            (merge current-approvals { rejection-count: (+ (get rejection-count current-approvals) u1) })
        )))
            (map-set milestone-approvals
                { grant-id: grant-id, milestone-id: milestone-id }
                new-approvals
            )
            (begin
                (if (>= (get approval-count new-approvals) (var-get approval-threshold))
                    (try! (finalize-milestone-approval grant-id milestone-id))
                    true
                )
                (ok true)
            )
        )
    )
)

(define-private (finalize-milestone-approval (grant-id uint) (milestone-id uint))
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (milestone (unwrap! (get-milestone grant-id milestone-id) ERR-MILESTONE-NOT-FOUND))
        (approvals (unwrap! (map-get? milestone-approvals { grant-id: grant-id, milestone-id: milestone-id }) ERR-MILESTONE-NOT-FOUND))
    )
        (try! (stx-transfer? (get amount milestone) tx-sender (get recipient grant)))
        (map-set milestones
            { grant-id: grant-id, milestone-id: milestone-id }
            (merge milestone { approved: true })
        )
        (map-set milestone-approvals
            { grant-id: grant-id, milestone-id: milestone-id }
            (merge approvals { finalized: true })
        )
        (map-set grants
            { grant-id: grant-id }
            (merge grant { 
                remaining-amount: (- (get remaining-amount grant) (get amount milestone))
            })
        )
        (ok true)
    )
)

(define-read-only (get-milestone-approvals (grant-id uint) (milestone-id uint))
    (map-get? milestone-approvals { grant-id: grant-id, milestone-id: milestone-id })
)

(define-read-only (get-validator-vote (grant-id uint) (milestone-id uint) (validator principal))
    (map-get? validator-votes { grant-id: grant-id, milestone-id: milestone-id, validator: validator })
)

(define-read-only (get-approval-threshold)
    (var-get approval-threshold)
)

(define-public (submit-milestone-report 
    (grant-id uint) 
    (milestone-id uint) 
    (progress-percentage uint) 
    (deliverable-url (string-ascii 200)) 
    (notes (string-ascii 500))
)
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (milestone (unwrap! (get-milestone grant-id milestone-id) ERR-MILESTONE-NOT-FOUND))
        (existing-report (map-get? milestone-reports { grant-id: grant-id, milestone-id: milestone-id }))
    )
        (asserts! (is-eq tx-sender (get recipient grant)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get completed milestone)) ERR-MILESTONE-ALREADY-COMPLETED)
        (asserts! (<= progress-percentage u100) ERR-INVALID-AMOUNT)
        (asserts! (is-none existing-report) ERR-REPORT-ALREADY-SUBMITTED)
        (map-set milestone-reports
            { grant-id: grant-id, milestone-id: milestone-id }
            {
                progress-percentage: progress-percentage,
                deliverable-url: deliverable-url,
                notes: notes,
                submitted-at: stacks-block-height,
                submitted: true
            }
        )
        (ok true)
    )
)

(define-public (update-milestone-report 
    (grant-id uint) 
    (milestone-id uint) 
    (progress-percentage uint) 
    (deliverable-url (string-ascii 200)) 
    (notes (string-ascii 500))
)
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (milestone (unwrap! (get-milestone grant-id milestone-id) ERR-MILESTONE-NOT-FOUND))
        (existing-report (unwrap! (map-get? milestone-reports { grant-id: grant-id, milestone-id: milestone-id }) ERR-REPORT-NOT-FOUND))
    )
        (asserts! (is-eq tx-sender (get recipient grant)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get completed milestone)) ERR-MILESTONE-ALREADY-COMPLETED)
        (asserts! (<= progress-percentage u100) ERR-INVALID-AMOUNT)
        (map-set milestone-reports
            { grant-id: grant-id, milestone-id: milestone-id }
            {
                progress-percentage: progress-percentage,
                deliverable-url: deliverable-url,
                notes: notes,
                submitted-at: (get submitted-at existing-report),
                submitted: true
            }
        )
        (ok true)
    )
)

(define-public (submit-milestone-with-report 
    (grant-id uint) 
    (milestone-id uint) 
    (progress-percentage uint) 
    (deliverable-url (string-ascii 200)) 
    (notes (string-ascii 500))
)
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (milestone (unwrap! (get-milestone grant-id milestone-id) ERR-MILESTONE-NOT-FOUND))
        (existing-report (map-get? milestone-reports { grant-id: grant-id, milestone-id: milestone-id }))
    )
        (asserts! (is-eq tx-sender (get recipient grant)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get completed milestone)) ERR-MILESTONE-ALREADY-COMPLETED)
        (asserts! (<= progress-percentage u100) ERR-INVALID-AMOUNT)
        (asserts! (is-eq progress-percentage u100) ERR-INVALID-AMOUNT)
        (map-set milestone-reports
            { grant-id: grant-id, milestone-id: milestone-id }
            {
                progress-percentage: progress-percentage,
                deliverable-url: deliverable-url,
                notes: notes,
                submitted-at: stacks-block-height,
                submitted: true
            }
        )
        (map-set milestones
            { grant-id: grant-id, milestone-id: milestone-id }
            (merge milestone { completed: true })
        )
        (ok true)
    )
)

(define-read-only (get-milestone-report (grant-id uint) (milestone-id uint))
    (map-get? milestone-reports { grant-id: grant-id, milestone-id: milestone-id })
)

(define-read-only (has-milestone-report (grant-id uint) (milestone-id uint))
    (match (get-milestone-report grant-id milestone-id)
        report (get submitted report)
        false
    )
)

(define-constant ERR-INVALID-CATEGORY (err u113))
(define-constant ERR-BUDGET-EXCEEDED (err u114))
(define-constant ERR-CATEGORY-NOT-FOUND (err u115))

(define-map grant-budget-categories
    { grant-id: uint }
    {
        development-budget: uint,
        testing-budget: uint,
        marketing-budget: uint,
        operations-budget: uint,
        other-budget: uint
    }
)

(define-map category-spending
    { grant-id: uint }
    {
        development-spent: uint,
        testing-spent: uint,
        marketing-spent: uint,
        operations-spent: uint,
        other-spent: uint
    }
)

(define-public (allocate-grant-budget 
    (grant-id uint)
    (development-budget uint)
    (testing-budget uint)
    (marketing-budget uint)
    (operations-budget uint)
    (other-budget uint)
)
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (total-allocated (+ development-budget (+ testing-budget (+ marketing-budget (+ operations-budget other-budget)))))
    )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq total-allocated (get total-amount grant)) ERR-INVALID-AMOUNT)
        (map-set grant-budget-categories
            { grant-id: grant-id }
            {
                development-budget: development-budget,
                testing-budget: testing-budget,
                marketing-budget: marketing-budget,
                operations-budget: operations-budget,
                other-budget: other-budget
            }
        )
        (map-set category-spending
            { grant-id: grant-id }
            {
                development-spent: u0,
                testing-spent: u0,
                marketing-spent: u0,
                operations-spent: u0,
                other-spent: u0
            }
        )
        (ok true)
    )
)

(define-public (add-categorized-milestone 
    (grant-id uint) 
    (milestone-id uint) 
    (amount uint) 
    (description (string-ascii 100))
    (category (string-ascii 20))
)
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (budget (unwrap! (map-get? grant-budget-categories { grant-id: grant-id }) ERR-CATEGORY-NOT-FOUND))
        (spending (default-to 
            { development-spent: u0, testing-spent: u0, marketing-spent: u0, operations-spent: u0, other-spent: u0 }
            (map-get? category-spending { grant-id: grant-id })
        ))
    )
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (if (is-eq category "development")
            (asserts! (<= (+ (get development-spent spending) amount) (get development-budget budget)) ERR-BUDGET-EXCEEDED)
            (if (is-eq category "testing")
                (asserts! (<= (+ (get testing-spent spending) amount) (get testing-budget budget)) ERR-BUDGET-EXCEEDED)
                (if (is-eq category "marketing")
                    (asserts! (<= (+ (get marketing-spent spending) amount) (get marketing-budget budget)) ERR-BUDGET-EXCEEDED)
                    (if (is-eq category "operations")
                        (asserts! (<= (+ (get operations-spent spending) amount) (get operations-budget budget)) ERR-BUDGET-EXCEEDED)
                        (if (is-eq category "other")
                            (asserts! (<= (+ (get other-spent spending) amount) (get other-budget budget)) ERR-BUDGET-EXCEEDED)
                            (asserts! false ERR-INVALID-CATEGORY)
                        )
                    )
                )
            )
        )
        (map-set milestones
            { grant-id: grant-id, milestone-id: milestone-id }
            {
                amount: amount,
                description: description,
                completed: false,
                approved: false
            }
        )
        (let ((new-spending 
            (if (is-eq category "development")
                (merge spending { development-spent: (+ (get development-spent spending) amount) })
                (if (is-eq category "testing")
                    (merge spending { testing-spent: (+ (get testing-spent spending) amount) })
                    (if (is-eq category "marketing")
                        (merge spending { marketing-spent: (+ (get marketing-spent spending) amount) })
                        (if (is-eq category "operations")
                            (merge spending { operations-spent: (+ (get operations-spent spending) amount) })
                            (merge spending { other-spent: (+ (get other-spent spending) amount) })
                        )
                    )
                )
            )
        ))
            (map-set category-spending { grant-id: grant-id } new-spending)
            (ok true)
        )
    )
)

(define-read-only (get-grant-budget (grant-id uint))
    (map-get? grant-budget-categories { grant-id: grant-id })
)

(define-read-only (get-category-spending (grant-id uint))
    (map-get? category-spending { grant-id: grant-id })
)

(define-read-only (get-budget-utilization (grant-id uint))
    (match (map-get? grant-budget-categories { grant-id: grant-id })
        budget (match (map-get? category-spending { grant-id: grant-id })
            spending (some {
                development-utilization: (if (> (get development-budget budget) u0) 
                    (/ (* (get development-spent spending) u100) (get development-budget budget)) 
                    u0),
                testing-utilization: (if (> (get testing-budget budget) u0) 
                    (/ (* (get testing-spent spending) u100) (get testing-budget budget)) 
                    u0),
                marketing-utilization: (if (> (get marketing-budget budget) u0) 
                    (/ (* (get marketing-spent spending) u100) (get marketing-budget budget)) 
                    u0),
                operations-utilization: (if (> (get operations-budget budget) u0) 
                    (/ (* (get operations-spent spending) u100) (get operations-budget budget)) 
                    u0),
                other-utilization: (if (> (get other-budget budget) u0) 
                    (/ (* (get other-spent spending) u100) (get other-budget budget)) 
                    u0)
            })
            none
        )
        none
    )
)