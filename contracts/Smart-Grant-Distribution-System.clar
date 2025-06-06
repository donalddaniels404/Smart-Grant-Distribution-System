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
