;; Corporate Risk Management Platform - Risk Identifier Contract
;; title: risk-identifier
;; version: 1.0.0
;; summary: Identifies potential business risks and vulnerabilities with automated scoring
;; description: This contract manages risk registration, assessment, tracking, and compliance reporting
;;             for corporate risk management. It provides transparent, blockchain-verified risk data.

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-RISK-NOT-FOUND (err u101))
(define-constant ERR-INVALID-RISK-LEVEL (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-ALREADY-ASSESSED (err u104))
(define-constant ERR-INVALID-SCORE (err u105))
(define-constant ERR-INSUFFICIENT-BALANCE (err u106))

;; Risk level constants
(define-constant RISK-LEVEL-LOW u1)
(define-constant RISK-LEVEL-MEDIUM u2)
(define-constant RISK-LEVEL-HIGH u3)
(define-constant RISK-LEVEL-CRITICAL u4)

;; Risk status constants
(define-constant STATUS-IDENTIFIED u1)
(define-constant STATUS-ASSESSED u2)
(define-constant STATUS-MITIGATING u3)
(define-constant STATUS-RESOLVED u4)
(define-constant STATUS-ACCEPTED u5)

;; Risk category constants
(define-constant CATEGORY-FINANCIAL u1)
(define-constant CATEGORY-OPERATIONAL u2)
(define-constant CATEGORY-STRATEGIC u3)
(define-constant CATEGORY-COMPLIANCE u4)
(define-constant CATEGORY-REPUTATIONAL u5)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-risk-id uint u1)
(define-data-var total-risks uint u0)
(define-data-var assessment-fee uint u1000000) ;; 1 STX fee for assessments
(define-data-var contract-balance uint u0)

;; Risk data structure
(define-map risks
  { risk-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    category: uint,
    level: uint,
    status: uint,
    impact-score: uint,
    probability-score: uint,
    overall-score: uint,
    identified-by: principal,
    identified-at: uint,
    last-updated: uint,
    mitigation-plan: (string-ascii 300),
    resolution-notes: (optional (string-ascii 300))
  }
)

;; Risk assessments by different stakeholders
(define-map risk-assessments
  { risk-id: uint, assessor: principal }
  {
    impact-score: uint,
    probability-score: uint,
    assessment-notes: (string-ascii 200),
    assessed-at: uint
  }
)

;; Risk history tracking
(define-map risk-history
  { risk-id: uint, sequence: uint }
  {
    action: (string-ascii 50),
    old-status: uint,
    new-status: uint,
    updated-by: principal,
    timestamp: uint,
    notes: (string-ascii 200)
  }
)

;; Authorized risk managers
(define-map authorized-managers
  { manager: principal }
  { authorized: bool, role: (string-ascii 50) }
)

;; Risk categories mapping for reporting
(define-map risk-categories
  { category-id: uint }
  { name: (string-ascii 50), description: (string-ascii 200) }
)

;; Public function: Register a new business risk
(define-public (register-risk 
                (title (string-ascii 100))
                (description (string-ascii 500))
                (category uint)
                (level uint)
                (impact-score uint)
                (probability-score uint)
                (mitigation-plan (string-ascii 300)))
  (let 
    (
      (risk-id (var-get next-risk-id))
      (overall-score (calculate-overall-score impact-score probability-score))
    )
    (asserts! (is-valid-risk-level level) ERR-INVALID-RISK-LEVEL)
    (asserts! (and (>= impact-score u1) (<= impact-score u10)) ERR-INVALID-SCORE)
    (asserts! (and (>= probability-score u1) (<= probability-score u10)) ERR-INVALID-SCORE)
    
    ;; Store the risk
    (map-set risks
      { risk-id: risk-id }
      {
        title: title,
        description: description,
        category: category,
        level: level,
        status: STATUS-IDENTIFIED,
        impact-score: impact-score,
        probability-score: probability-score,
        overall-score: overall-score,
        identified-by: tx-sender,
        identified-at: block-height,
        last-updated: block-height,
        mitigation-plan: mitigation-plan,
        resolution-notes: none
      }
    )
    
    ;; Add to history
    (map-set risk-history
      { risk-id: risk-id, sequence: u1 }
      {
        action: "RISK_REGISTERED",
        old-status: u0,
        new-status: STATUS-IDENTIFIED,
        updated-by: tx-sender,
        timestamp: block-height,
        notes: "New risk registered in system"
      }
    )
    
    ;; Update counters
    (var-set next-risk-id (+ risk-id u1))
    (var-set total-risks (+ (var-get total-risks) u1))
    
    (ok risk-id)
  )
)

;; Public function: Assess an existing risk
(define-public (assess-risk 
                (risk-id uint)
                (impact-score uint)
                (probability-score uint)
                (assessment-notes (string-ascii 200)))
  (let
    (
      (risk-data (unwrap! (map-get? risks { risk-id: risk-id }) ERR-RISK-NOT-FOUND))
      (assessment-key { risk-id: risk-id, assessor: tx-sender })
    )
    
    (asserts! (and (>= impact-score u1) (<= impact-score u10)) ERR-INVALID-SCORE)
    (asserts! (and (>= probability-score u1) (<= probability-score u10)) ERR-INVALID-SCORE)
    (asserts! (is-none (map-get? risk-assessments assessment-key)) ERR-ALREADY-ASSESSED)
    
    ;; Pay assessment fee
    (try! (stx-transfer? (var-get assessment-fee) tx-sender (as-contract tx-sender)))
    (var-set contract-balance (+ (var-get contract-balance) (var-get assessment-fee)))
    
    ;; Store assessment
    (map-set risk-assessments
      assessment-key
      {
        impact-score: impact-score,
        probability-score: probability-score,
        assessment-notes: assessment-notes,
        assessed-at: block-height
      }
    )
    
    ;; Update risk status if first assessment
    (if (is-eq (get status risk-data) STATUS-IDENTIFIED)
      (begin
        (map-set risks
          { risk-id: risk-id }
          (merge risk-data { 
            status: STATUS-ASSESSED,
            last-updated: block-height
          })
        )
        
        ;; Add to history
        (map-set risk-history
          { risk-id: risk-id, sequence: u2 }
          {
            action: "RISK_ASSESSED",
            old-status: STATUS-IDENTIFIED,
            new-status: STATUS-ASSESSED,
            updated-by: tx-sender,
            timestamp: block-height,
            notes: "Risk assessment completed"
          }
        )
      )
      true
    )
    
    (ok true)
  )
)

;; Public function: Update risk status
(define-public (update-risk-status 
                (risk-id uint)
                (new-status uint)
                (notes (string-ascii 200)))
  (let
    (
      (risk-data (unwrap! (map-get? risks { risk-id: risk-id }) ERR-RISK-NOT-FOUND))
      (old-status (get status risk-data))
      (sequence (+ u2 u1)) ;; Simple sequence incrementer
    )
    
    (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)
    (asserts! (or (is-eq tx-sender (var-get contract-owner)) 
                  (is-authorized-manager tx-sender)) ERR-NOT-AUTHORIZED)
    
    ;; Update risk
    (map-set risks
      { risk-id: risk-id }
      (merge risk-data { 
        status: new-status,
        last-updated: block-height
      })
    )
    
    ;; Add to history
    (map-set risk-history
      { risk-id: risk-id, sequence: sequence }
      {
        action: "STATUS_UPDATED",
        old-status: old-status,
        new-status: new-status,
        updated-by: tx-sender,
        timestamp: block-height,
        notes: notes
      }
    )
    
    (ok true)
  )
)

;; Public function: Add resolution notes to resolved risks
(define-public (add-resolution-notes 
                (risk-id uint)
                (resolution-notes (string-ascii 300)))
  (let
    (
      (risk-data (unwrap! (map-get? risks { risk-id: risk-id }) ERR-RISK-NOT-FOUND))
    )
    
    (asserts! (is-eq (get status risk-data) STATUS-RESOLVED) ERR-INVALID-STATUS)
    (asserts! (or (is-eq tx-sender (var-get contract-owner))
                  (is-eq tx-sender (get identified-by risk-data))) ERR-NOT-AUTHORIZED)
    
    (map-set risks
      { risk-id: risk-id }
      (merge risk-data { 
        resolution-notes: (some resolution-notes),
        last-updated: block-height
      })
    )
    
    (ok true)
  )
)

;; Public function: Authorize risk managers
(define-public (authorize-manager 
                (manager principal)
                (role (string-ascii 50)))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    
    (map-set authorized-managers
      { manager: manager }
      { authorized: true, role: role }
    )
    
    (ok true)
  )
)

;; Read-only function: Get risk information
(define-read-only (get-risk-info (risk-id uint))
  (map-get? risks { risk-id: risk-id })
)

;; Read-only function: Get risk assessment by assessor
(define-read-only (get-risk-assessment (risk-id uint) (assessor principal))
  (map-get? risk-assessments { risk-id: risk-id, assessor: assessor })
)

;; Read-only function: Get risk history entry
(define-read-only (get-risk-history (risk-id uint) (sequence uint))
  (map-get? risk-history { risk-id: risk-id, sequence: sequence })
)

;; Read-only function: Check if user is authorized manager
(define-read-only (is-authorized-manager (user principal))
  (default-to false 
    (get authorized (map-get? authorized-managers { manager: user }))
  )
)

;; Read-only function: Get contract statistics
(define-read-only (get-contract-stats)
  {
    total-risks: (var-get total-risks),
    next-risk-id: (var-get next-risk-id),
    contract-balance: (var-get contract-balance),
    assessment-fee: (var-get assessment-fee),
    contract-owner: (var-get contract-owner)
  }
)

;; Read-only function: Generate compliance report for risk category
(define-read-only (generate-compliance-report (category uint))
  {
    category: category,
    report-generated-at: block-height,
    total-contract-risks: (var-get total-risks),
    contract-balance: (var-get contract-balance)
  }
)

;; Private function: Calculate overall risk score
(define-private (calculate-overall-score (impact uint) (probability uint))
  (/ (* impact probability) u2) ;; Simple average for demonstration
)

;; Private function: Validate risk level
(define-private (is-valid-risk-level (level uint))
  (and (>= level RISK-LEVEL-LOW) (<= level RISK-LEVEL-CRITICAL))
)

;; Private function: Validate risk status
(define-private (is-valid-status (status uint))
  (and (>= status STATUS-IDENTIFIED) (<= status STATUS-ACCEPTED))
)
