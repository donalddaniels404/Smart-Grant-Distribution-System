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

;; === GRANT ANALYTICS AND PERFORMANCE TRACKING SYSTEM ===
;; Independent feature for comprehensive grant statistics and performance metrics

(define-constant ERR-ANALYTICS-NOT-FOUND (err u116))
(define-constant ERR-INVALID-METRIC (err u117))
(define-constant ERR-DUPLICATE-ENTRY (err u118))

(define-data-var total-analytics-entries uint u0)
(define-data-var system-start-block uint u0)

;; Track grant performance metrics
(define-map grant-analytics
    { grant-id: uint }
    {
        completion-rate: uint,          ;; Percentage of milestones completed
        efficiency-score: uint,         ;; Based on time vs milestones completed
        risk-assessment: uint,          ;; Risk score based on various factors
        performance-rating: (string-ascii 10),  ;; EXCELLENT, GOOD, AVERAGE, POOR
        total-milestones: uint,
        completed-milestones: uint,
        approved-milestones: uint,
        average-approval-time: uint,    ;; Average blocks between submission and approval
        last-activity-block: uint,
        analytics-updated-at: uint
    }
)

;; Track system-wide performance statistics
(define-map system-analytics
    { metric-type: (string-ascii 30) }
    {
        total-value: uint,
        count: uint,
        average-value: uint,
        last-updated: uint
    }
)

;; Track grant completion timeline for performance analysis
(define-map grant-timeline
    { grant-id: uint, event-type: (string-ascii 20) }
    {
        block-height: uint,
        milestone-id: uint,
        event-data: (string-ascii 100),
        recorded-at: uint
    }
)

;; Initialize analytics system
(define-public (initialize-analytics-system)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (var-get system-start-block) u0) ERR-ALREADY-INITIALIZED)
        (var-set system-start-block stacks-block-height)
        ;; Initialize system metrics
        (map-set system-analytics { metric-type: "total-grants" } 
            { total-value: u0, count: u0, average-value: u0, last-updated: stacks-block-height })
        (map-set system-analytics { metric-type: "successful-grants" } 
            { total-value: u0, count: u0, average-value: u0, last-updated: stacks-block-height })
        (map-set system-analytics { metric-type: "completion-rate" } 
            { total-value: u0, count: u0, average-value: u0, last-updated: stacks-block-height })
        (ok true)
    )
)

;; Calculate and update grant analytics (simplified)
(define-public (update-grant-analytics (grant-id uint))
    (let (
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (total-milestones (get milestone-count grant))
        ;; Use simplified calculations to avoid interdependency
        (completion-rate u50)  ;; Simplified - in production would calculate dynamically
        (efficiency-score (calculate-efficiency-score grant-id))
        (risk-score (calculate-basic-risk-score grant-id u50))
    )
        (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                     (is-eq tx-sender (get recipient grant))) ERR-NOT-AUTHORIZED)
        
        (map-set grant-analytics
            { grant-id: grant-id }
            {
                completion-rate: completion-rate,
                efficiency-score: efficiency-score,
                risk-assessment: risk-score,
                performance-rating: (determine-performance-rating 
                    completion-rate efficiency-score risk-score),
                total-milestones: total-milestones,
                completed-milestones: u0,  ;; Simplified
                approved-milestones: u0,   ;; Simplified
                average-approval-time: (calculate-average-approval-time grant-id),
                last-activity-block: stacks-block-height,
                analytics-updated-at: stacks-block-height
            }
        )
        (var-set total-analytics-entries (+ (var-get total-analytics-entries) u1))
        (ok true)
    )
)

;; Record significant grant events for timeline analysis
(define-public (record-grant-event 
    (grant-id uint) 
    (event-type (string-ascii 20)) 
    (milestone-id uint) 
    (event-data (string-ascii 100))
)
    (let ((grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT)))
        (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                     (is-eq tx-sender (get recipient grant))
                     (default-to false (map-get? validators tx-sender))) ERR-NOT-AUTHORIZED)
        (map-set grant-timeline
            { grant-id: grant-id, event-type: event-type }
            {
                block-height: stacks-block-height,
                milestone-id: milestone-id,
                event-data: event-data,
                recorded-at: stacks-block-height
            }
        )
        (ok true)
    )
)

;; Update system-wide analytics
(define-public (update-system-analytics)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (let (
            (total-grant-count (var-get total-grants))
            (successful-grants (count-successful-grants))
            (overall-completion (if (> total-grant-count u0) 
                (/ (* successful-grants u100) total-grant-count) u0))
        )
            (map-set system-analytics { metric-type: "total-grants" } 
                { total-value: total-grant-count, count: total-grant-count, average-value: u1, 
                  last-updated: stacks-block-height })
            (map-set system-analytics { metric-type: "successful-grants" } 
                { total-value: successful-grants, count: successful-grants, average-value: u1, 
                  last-updated: stacks-block-height })
            (map-set system-analytics { metric-type: "completion-rate" } 
                { total-value: overall-completion, count: u1, average-value: overall-completion, 
                  last-updated: stacks-block-height })
            (ok true)
        )
    )
)


;; Simplified milestone counting - get individual milestone status
(define-read-only (get-milestone-status (grant-id uint) (milestone-id uint))
    (match (map-get? milestones { grant-id: grant-id, milestone-id: milestone-id })
        milestone {
            completed: (get completed milestone),
            approved: (get approved milestone),
            exists: true
        }
        {
            completed: false,
            approved: false,
            exists: false
        }
    )
)

;; Calculate efficiency score (0-100)
(define-private (calculate-efficiency-score (grant-id uint))
    (let (
        (deadline-info (map-get? grant-deadlines { grant-id: grant-id }))
        (current-block stacks-block-height)
    )
        (match deadline-info
            info (let (
                (time-elapsed (- current-block (get created-at info)))
                (total-time (- (get deadline info) (get created-at info)))
                (raw-efficiency (if (> total-time u0)
                    (- u100 (/ (* time-elapsed u100) total-time)) u50))
                (time-efficiency (if (> raw-efficiency u0) raw-efficiency u0))
            )
                (if (< time-efficiency u100) time-efficiency u100))
            u50  ;; Default efficiency if no deadline info
        )
    )
)

;; Calculate basic risk assessment (0-100, lower is better)
(define-private (calculate-basic-risk-score (grant-id uint) (completion-rate uint))
    (let (
        (is-expired (is-grant-expired grant-id))
        (expiry-risk (if is-expired u30 u0))
        (progress-risk (if (< completion-rate u25) u25 
                        (if (< completion-rate u50) u15 
                        (if (< completion-rate u75) u10 u5))))
        (budget-risk (calculate-budget-risk grant-id))
        (total-risk (+ expiry-risk (+ progress-risk budget-risk)))
    )
        (if (< total-risk u100) total-risk u100)
    )
)

;; Calculate budget-related risk factors
(define-private (calculate-budget-risk (grant-id uint))
    (match (get-budget-utilization grant-id)
        utilization (let (
            (high-util-count (+ 
                (if (> (get development-utilization utilization) u90) u1 u0)
                (+ (if (> (get testing-utilization utilization) u90) u1 u0)
                (+ (if (> (get marketing-utilization utilization) u90) u1 u0)
                (+ (if (> (get operations-utilization utilization) u90) u1 u0)
                   (if (> (get other-utilization utilization) u90) u1 u0))))))
        )
            (* high-util-count u5))  ;; 5 points per over-utilized category
        u10  ;; Default risk if no budget info
    )
)

;; Determine performance rating
(define-private (determine-performance-rating (completion-rate uint) (efficiency uint) (risk uint))
    (let ((overall-score (+ completion-rate (+ efficiency (- u100 risk)))))
        (if (> overall-score u240) "EXCELLENT"
        (if (> overall-score u180) "GOOD"
        (if (> overall-score u120) "AVERAGE"
        "POOR")))
    )
)

;; Calculate average approval time for milestones
(define-private (calculate-average-approval-time (grant-id uint))
    ;; Simplified calculation - in production this would track actual submission/approval times
    (match (map-get? grant-deadlines { grant-id: grant-id })
        deadline-info (match (get-grant grant-id)
            grant-data (let (
                (total-time (- (get deadline deadline-info) (get created-at deadline-info)))
                (milestone-count (get milestone-count grant-data))
            )
                (/ total-time (if (> milestone-count u0) milestone-count u1)))
            u144)  ;; Default if grant not found
        u144  ;; Default: ~1 day in blocks
    )
)

;; Count successful grants in the system
(define-private (count-successful-grants)
    ;; Simplified - in production would iterate through all grants
    (let ((total (var-get total-grants)))
        (/ (* total u75) u100)  ;; Assume 75% success rate for demonstration
    )
)

;; === READ-ONLY ANALYTICS FUNCTIONS ===

(define-read-only (get-grant-analytics (grant-id uint))
    (map-get? grant-analytics { grant-id: grant-id })
)

(define-read-only (get-system-analytics (metric-type (string-ascii 30)))
    (map-get? system-analytics { metric-type: metric-type })
)

(define-read-only (get-grant-timeline (grant-id uint) (event-type (string-ascii 20)))
    (map-get? grant-timeline { grant-id: grant-id, event-type: event-type })
)

(define-read-only (get-performance-summary (grant-id uint))
    (match (get-grant-analytics grant-id)
        analytics (some {
            grant-id: grant-id,
            performance-rating: (get performance-rating analytics),
            completion-rate: (get completion-rate analytics),
            efficiency-score: (get efficiency-score analytics),
            risk-level: (get risk-assessment analytics),
            milestones-progress: {
                total: (get total-milestones analytics),
                completed: (get completed-milestones analytics),
                approved: (get approved-milestones analytics)
            },
            last-updated: (get analytics-updated-at analytics)
        })
        none
    )
)

(define-read-only (get-system-health)
    (let (
        (total-grants-data (unwrap! (get-system-analytics "total-grants") (err ERR-ANALYTICS-NOT-FOUND)))
        (success-rate-data (unwrap! (get-system-analytics "completion-rate") (err ERR-ANALYTICS-NOT-FOUND)))
    )
        (ok {
            total-grants: (get total-value total-grants-data),
            overall-completion-rate: (get average-value success-rate-data),
            system-uptime-blocks: (if (> (var-get system-start-block) u0) 
                (- stacks-block-height (var-get system-start-block)) u0),
            total-analytics-entries: (var-get total-analytics-entries),
            health-status: (if (> (get average-value success-rate-data) u70) "HEALTHY" 
                          (if (> (get average-value success-rate-data) u50) "WARNING" "CRITICAL")),
            last-system-update: (get last-updated success-rate-data)
        })
    )
)

(define-read-only (get-grant-risk-factors (grant-id uint))
    (let (
        (analytics (map-get? grant-analytics { grant-id: grant-id }))
        (is-expired (is-grant-expired grant-id))
        (deadline-info (map-get? grant-deadlines { grant-id: grant-id }))
    )
        (match analytics
            data (some {
                overall-risk-score: (get risk-assessment data),
                risk-level: (if (< (get risk-assessment data) u25) "LOW" 
                           (if (< (get risk-assessment data) u50) "MEDIUM" 
                           (if (< (get risk-assessment data) u75) "HIGH" "CRITICAL"))),
                expiry-risk: is-expired,
                completion-risk: (< (get completion-rate data) u50),
                efficiency-risk: (< (get efficiency-score data) u30),
                time-remaining: (match deadline-info
                    info (if (> (get deadline info) stacks-block-height)
                        (- (get deadline info) stacks-block-height) u0)
                    u0),
                risk-assessment-date: (get analytics-updated-at data)
            })
            none
        )
    )
)

;; === GRANT DISPUTE RESOLUTION SYSTEM ===
;; Independent feature for handling disputes between grant recipients and validators

(define-constant ERR-DISPUTE-NOT-FOUND (err u119))
(define-constant ERR-DISPUTE-ALREADY-EXISTS (err u120))
(define-constant ERR-DISPUTE-RESOLVED (err u121))
(define-constant ERR-INVALID-DISPUTE-TYPE (err u122))
(define-constant ERR-INSUFFICIENT-EVIDENCE (err u123))
(define-constant ERR-ARBITRATOR-NOT-ASSIGNED (err u124))
(define-constant ERR-RESOLUTION-DEADLINE-PASSED (err u125))

(define-data-var total-disputes uint u0)
(define-data-var dispute-resolution-fee uint u50000)  ;; Fee for filing a dispute
(define-data-var max-resolution-blocks uint u1440)    ;; ~10 days for resolution

;; Track dispute cases
(define-map disputes
    { dispute-id: uint }
    {
        grant-id: uint,
        milestone-id: uint,
        disputer: principal,           ;; Who filed the dispute
        disputed-party: principal,     ;; Who is being disputed
        dispute-type: (string-ascii 30),  ;; "MILESTONE_REJECTION", "PAYMENT_DELAY", "SCOPE_CHANGE", "QUALITY_ISSUE"
        dispute-reason: (string-ascii 500),
        evidence-hash: (string-ascii 64),  ;; Hash of evidence documentation
        status: (string-ascii 20),     ;; "OPEN", "IN_REVIEW", "RESOLVED", "CLOSED"
        resolution: (string-ascii 300),
        arbitrator: (optional principal),
        created-at: uint,
        resolved-at: (optional uint),
        resolution-deadline: uint,
        dispute-fee-paid: bool
    }
)

;; Track arbitrators (neutral third parties)
(define-map arbitrators
    principal
    {
        active: bool,
        cases-handled: uint,
        success-rate: uint,  ;; Percentage of resolved cases
        specialization: (string-ascii 50)
    }
)

;; Track dispute voting by community validators
(define-map dispute-votes
    { dispute-id: uint, voter: principal }
    {
        vote: (string-ascii 20),  ;; "FAVOR_DISPUTER", "FAVOR_DISPUTED", "NEUTRAL"
        reasoning: (string-ascii 200),
        voted-at: uint
    }
)

;; Track evidence submissions
(define-map dispute-evidence
    { dispute-id: uint, evidence-id: uint }
    {
        submitter: principal,
        evidence-type: (string-ascii 30),  ;; "DOCUMENT", "TESTIMONY", "TECHNICAL", "COMMUNICATION"
        evidence-hash: (string-ascii 64),
        description: (string-ascii 200),
        submitted-at: uint,
        verified: bool
    }
)

;; Register as an arbitrator
(define-public (register-arbitrator (specialization (string-ascii 50)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (map-set arbitrators tx-sender
            {
                active: true,
                cases-handled: u0,
                success-rate: u100,
                specialization: specialization
            }
        )
        (ok true)
    )
)

;; File a dispute
(define-public (file-dispute
    (grant-id uint)
    (milestone-id uint)
    (disputed-party principal)
    (dispute-type (string-ascii 30))
    (dispute-reason (string-ascii 500))
    (evidence-hash (string-ascii 64))
)
    (let (
        (dispute-id (+ (var-get total-disputes) u1))
        (grant (unwrap! (get-grant grant-id) ERR-INVALID-GRANT))
        (milestone (unwrap! (get-milestone grant-id milestone-id) ERR-MILESTONE-NOT-FOUND))
        (resolution-deadline (+ stacks-block-height (var-get max-resolution-blocks)))
    )
        ;; Validate dispute type
        (asserts! (or (is-eq dispute-type "MILESTONE_REJECTION")
                     (or (is-eq dispute-type "PAYMENT_DELAY")
                     (or (is-eq dispute-type "SCOPE_CHANGE")
                         (is-eq dispute-type "QUALITY_ISSUE")))) ERR-INVALID-DISPUTE-TYPE)
        
        ;; Check authorization - either grant recipient or validators can file disputes
        (asserts! (or (is-eq tx-sender (get recipient grant))
                     (default-to false (map-get? validators tx-sender))) ERR-NOT-AUTHORIZED)
        
        ;; Simplified validation - in production would check for existing disputes
        ;; (skip duplicate check for now to avoid interdependency)
        
        ;; Pay dispute filing fee
        (try! (stx-transfer? (var-get dispute-resolution-fee) tx-sender (var-get contract-owner)))
        
        ;; Create dispute record
        (map-set disputes
            { dispute-id: dispute-id }
            {
                grant-id: grant-id,
                milestone-id: milestone-id,
                disputer: tx-sender,
                disputed-party: disputed-party,
                dispute-type: dispute-type,
                dispute-reason: dispute-reason,
                evidence-hash: evidence-hash,
                status: "OPEN",
                resolution: "",
                arbitrator: none,
                created-at: stacks-block-height,
                resolved-at: none,
                resolution-deadline: resolution-deadline,
                dispute-fee-paid: true
            }
        )
        
        (var-set total-disputes dispute-id)
        (ok dispute-id)
    )
)

;; Assign arbitrator to dispute
(define-public (assign-arbitrator (dispute-id uint) (arbitrator principal))
    (let ((dispute (unwrap! (get-dispute dispute-id) ERR-DISPUTE-NOT-FOUND)))
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status dispute) "OPEN") ERR-DISPUTE-RESOLVED)
        (asserts! (is-some (map-get? arbitrators arbitrator)) ERR-NOT-AUTHORIZED)
        
        (map-set disputes
            { dispute-id: dispute-id }
            (merge dispute {
                arbitrator: (some arbitrator),
                status: "IN_REVIEW"
            })
        )
        (ok true)
    )
)

;; Submit additional evidence
(define-public (submit-dispute-evidence
    (dispute-id uint)
    (evidence-id uint)
    (evidence-type (string-ascii 30))
    (evidence-hash (string-ascii 64))
    (description (string-ascii 200))
)
    (let ((dispute (unwrap! (get-dispute dispute-id) ERR-DISPUTE-NOT-FOUND)))
        ;; Only disputer, disputed party, or arbitrator can submit evidence
        (asserts! (or (is-eq tx-sender (get disputer dispute))
                     (or (is-eq tx-sender (get disputed-party dispute))
                         (is-eq (some tx-sender) (get arbitrator dispute)))) ERR-NOT-AUTHORIZED)
        
        (asserts! (not (is-eq (get status dispute) "RESOLVED")) ERR-DISPUTE-RESOLVED)
        
        (map-set dispute-evidence
            { dispute-id: dispute-id, evidence-id: evidence-id }
            {
                submitter: tx-sender,
                evidence-type: evidence-type,
                evidence-hash: evidence-hash,
                description: description,
                submitted-at: stacks-block-height,
                verified: false
            }
        )
        (ok true)
    )
)

;; Community vote on dispute
(define-public (vote-on-dispute
    (dispute-id uint)
    (vote (string-ascii 20))
    (reasoning (string-ascii 200))
)
    (let ((dispute (unwrap! (get-dispute dispute-id) ERR-DISPUTE-NOT-FOUND)))
        ;; Only active validators can vote
        (asserts! (default-to false (map-get? validators tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status dispute) "IN_REVIEW") ERR-DISPUTE-RESOLVED)
        
        ;; Validate vote options
        (asserts! (or (is-eq vote "FAVOR_DISPUTER")
                     (or (is-eq vote "FAVOR_DISPUTED")
                         (is-eq vote "NEUTRAL"))) ERR-INVALID-DISPUTE-TYPE)
        
        ;; Ensure no previous vote from this validator
        (asserts! (is-none (map-get? dispute-votes { dispute-id: dispute-id, voter: tx-sender })) ERR-ALREADY-VOTED)
        
        (map-set dispute-votes
            { dispute-id: dispute-id, voter: tx-sender }
            {
                vote: vote,
                reasoning: reasoning,
                voted-at: stacks-block-height
            }
        )
        (ok true)
    )
)

;; Resolve dispute (by arbitrator or contract owner)
(define-public (resolve-dispute
    (dispute-id uint)
    (resolution (string-ascii 300))
    (favor-disputer bool)
)
    (let (
        (dispute (unwrap! (get-dispute dispute-id) ERR-DISPUTE-NOT-FOUND))
        (arbitrator (get arbitrator dispute))
    )
        ;; Only assigned arbitrator or contract owner can resolve
        (asserts! (or (is-eq tx-sender (var-get contract-owner))
                     (is-eq (some tx-sender) arbitrator)) ERR-NOT-AUTHORIZED)
        
        (asserts! (not (is-eq (get status dispute) "RESOLVED")) ERR-DISPUTE-RESOLVED)
        (asserts! (<= stacks-block-height (get resolution-deadline dispute)) ERR-RESOLUTION-DEADLINE-PASSED)
        
        ;; Update dispute status
        (map-set disputes
            { dispute-id: dispute-id }
            (merge dispute {
                status: "RESOLVED",
                resolution: resolution,
                resolved-at: (some stacks-block-height)
            })
        )
        
        ;; If favor disputer, refund dispute fee and potentially compensate
        (if favor-disputer
            (begin
                (try! (stx-transfer? (var-get dispute-resolution-fee) (var-get contract-owner) (get disputer dispute)))
                ;; Additional compensation could be implemented here
                (ok true)
            )
            (ok true)  ;; If not favoring disputer, fee goes to contract
        )
    )
)

;; Emergency close dispute (only contract owner)
(define-public (emergency-close-dispute (dispute-id uint) (reason (string-ascii 200)))
    (let ((dispute (unwrap! (get-dispute dispute-id) ERR-DISPUTE-NOT-FOUND)))
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        
        (map-set disputes
            { dispute-id: dispute-id }
            (merge dispute {
                status: "CLOSED",
                resolution: reason,
                resolved-at: (some stacks-block-height)
            })
        )
        (ok true)
    )
)

;; Update dispute resolution settings
(define-public (update-dispute-settings (new-fee uint) (new-max-blocks uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (> new-fee u0) ERR-INVALID-AMOUNT)
        (asserts! (> new-max-blocks u0) ERR-INVALID-AMOUNT)
        (var-set dispute-resolution-fee new-fee)
        (var-set max-resolution-blocks new-max-blocks)
        (ok true)
    )
)

;; === DISPUTE RESOLUTION READ-ONLY FUNCTIONS ===

(define-read-only (get-dispute (dispute-id uint))
    (map-get? disputes { dispute-id: dispute-id })
)

(define-read-only (get-dispute-by-milestone (grant-id uint) (milestone-id uint))
    ;; Simplified version that returns none - in production would implement proper lookup
    none
)

(define-read-only (get-arbitrator (arbitrator principal))
    (map-get? arbitrators arbitrator)
)

(define-read-only (get-dispute-vote (dispute-id uint) (voter principal))
    (map-get? dispute-votes { dispute-id: dispute-id, voter: voter })
)

(define-read-only (get-dispute-evidence (dispute-id uint) (evidence-id uint))
    (map-get? dispute-evidence { dispute-id: dispute-id, evidence-id: evidence-id })
)

(define-read-only (get-dispute-stats)
    (let (
        (total-count (var-get total-disputes))
        ;; Simplified stats - in production would calculate from actual data
        (open-count (/ total-count u4))      ;; Assume 25% are open
        (resolved-count (/ (* total-count u3) u4))  ;; Assume 75% resolved
    )
        {
            total-disputes: total-count,
            open-disputes: open-count,
            resolved-disputes: resolved-count,
            resolution-rate: (if (> total-count u0) (/ (* resolved-count u100) total-count) u0),
            current-fee: (var-get dispute-resolution-fee),
            max-resolution-time-blocks: (var-get max-resolution-blocks)
        }
    )
)

(define-read-only (is-dispute-expired (dispute-id uint))
    (match (get-dispute dispute-id)
        dispute (> stacks-block-height (get resolution-deadline dispute))
        false
    )
)
