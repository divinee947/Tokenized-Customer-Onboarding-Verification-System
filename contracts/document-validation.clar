;; Document Validation Contract
;; Handles validation of customer onboarding documents

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-DOCUMENT-NOT-FOUND (err u301))
(define-constant ERR-DOCUMENT-ALREADY-EXISTS (err u302))
(define-constant ERR-INVALID-DOCUMENT-TYPE (err u303))
(define-constant ERR-DOCUMENT-EXPIRED (err u304))

;; Data Variables
(define-data-var next-document-id uint u1)
(define-data-var document-validity-period uint u26280) ;; ~6 months in blocks

;; Document Types
(define-constant DOC-TYPE-ID u1)
(define-constant DOC-TYPE-PROOF-OF-ADDRESS u2)
(define-constant DOC-TYPE-INCOME-STATEMENT u3)
(define-constant DOC-TYPE-BANK-STATEMENT u4)
(define-constant DOC-TYPE-EMPLOYMENT-LETTER u5)
(define-constant DOC-TYPE-TAX-RETURN u6)

;; Data Maps
(define-map documents
  { document-id: uint }
  {
    customer: principal,
    document-type: uint,
    document-hash: (buff 32),
    validation-status: (string-ascii 20),
    validated-by: (optional principal),
    submission-block: uint,
    validation-block: uint,
    expiry-block: uint,
    is-active: bool
  }
)

(define-map customer-documents
  { customer: principal, document-type: uint }
  { document-id: uint }
)

(define-map document-types
  { type-id: uint }
  {
    name: (string-ascii 50),
    required-for-levels: (list 3 uint),
    validation-criteria: (string-ascii 100),
    is-active: bool
  }
)

(define-map document-validation-history
  { document-id: uint, validator: principal }
  { validation-result: (string-ascii 20), validation-block: uint, notes: (string-ascii 200) }
)

;; Initialize document types
(map-set document-types { type-id: DOC-TYPE-ID }
  { name: "Government ID", required-for-levels: (list u1 u2 u3), validation-criteria: "Valid government-issued photo ID", is-active: true })
(map-set document-types { type-id: DOC-TYPE-PROOF-OF-ADDRESS }
  { name: "Proof of Address", required-for-levels: (list u1 u2 u3), validation-criteria: "Recent utility bill or bank statement", is-active: true })
(map-set document-types { type-id: DOC-TYPE-INCOME-STATEMENT }
  { name: "Income Statement", required-for-levels: (list u2 u3), validation-criteria: "Recent pay stub or income verification", is-active: true })
(map-set document-types { type-id: DOC-TYPE-BANK-STATEMENT }
  { name: "Bank Statement", required-for-levels: (list u2 u3), validation-criteria: "Recent bank statement showing transactions", is-active: true })
(map-set document-types { type-id: DOC-TYPE-EMPLOYMENT-LETTER }
  { name: "Employment Letter", required-for-levels: (list u3), validation-criteria: "Official employment verification letter", is-active: true })
(map-set document-types { type-id: DOC-TYPE-TAX-RETURN }
  { name: "Tax Return", required-for-levels: (list u3), validation-criteria: "Recent tax return or tax assessment", is-active: true })

;; Public Functions

;; Submit document for validation
(define-public (submit-document (document-type uint) (document-hash (buff 32)))
  (let
    (
      (document-id (var-get next-document-id))
      (customer tx-sender)
      (expiry-block (+ block-height (var-get document-validity-period)))
    )
    (asserts! (is-some (map-get? document-types { type-id: document-type })) ERR-INVALID-DOCUMENT-TYPE)
    (asserts! (is-none (map-get? customer-documents { customer: customer, document-type: document-type })) ERR-DOCUMENT-ALREADY-EXISTS)

    (map-set documents
      { document-id: document-id }
      {
        customer: customer,
        document-type: document-type,
        document-hash: document-hash,
        validation-status: "pending",
        validated-by: none,
        submission-block: block-height,
        validation-block: u0,
        expiry-block: expiry-block,
        is-active: true
      }
    )

    (map-set customer-documents
      { customer: customer, document-type: document-type }
      { document-id: document-id }
    )

    (var-set next-document-id (+ document-id u1))
    (ok document-id)
  )
)

;; Validate document (called by qualified specialist)
(define-public (validate-document (document-id uint) (validation-status (string-ascii 20)) (notes (string-ascii 200)))
  (let
    (
      (document (unwrap! (map-get? documents { document-id: document-id }) ERR-DOCUMENT-NOT-FOUND))
      (validator tx-sender)
    )
    ;; In a real implementation, we would check validator qualification here

    (map-set documents
      { document-id: document-id }
      (merge document {
        validation-status: validation-status,
        validated-by: (some validator),
        validation-block: block-height
      })
    )

    (map-set document-validation-history
      { document-id: document-id, validator: validator }
      { validation-result: validation-status, validation-block: block-height, notes: notes }
    )
    (ok true)
  )
)

;; Resubmit document (for rejected documents)
(define-public (resubmit-document (document-id uint) (new-document-hash (buff 32)))
  (let
    (
      (document (unwrap! (map-get? documents { document-id: document-id }) ERR-DOCUMENT-NOT-FOUND))
      (expiry-block (+ block-height (var-get document-validity-period)))
    )
    (asserts! (is-eq tx-sender (get customer document)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get validation-status document) "rejected") ERR-NOT-AUTHORIZED)

    (map-set documents
      { document-id: document-id }
      (merge document {
        document-hash: new-document-hash,
        validation-status: "pending",
        validated-by: none,
        submission-block: block-height,
        validation-block: u0,
        expiry-block: expiry-block
      })
    )
    (ok true)
  )
)

;; Update document type status
(define-public (update-document-type-status (type-id uint) (is-active bool))
  (let
    (
      (doc-type (unwrap! (map-get? document-types { type-id: type-id }) ERR-INVALID-DOCUMENT-TYPE))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set document-types
      { type-id: type-id }
      (merge doc-type { is-active: is-active })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get document information
(define-read-only (get-document (document-id uint))
  (map-get? documents { document-id: document-id })
)

;; Get customer document by type
(define-read-only (get-customer-document (customer principal) (document-type uint))
  (match (map-get? customer-documents { customer: customer, document-type: document-type })
    doc-data (map-get? documents { document-id: (get document-id doc-data) })
    none
  )
)

;; Check if document is validated
(define-read-only (is-document-validated (document-id uint))
  (match (map-get? documents { document-id: document-id })
    document (and
               (get is-active document)
               (is-eq (get validation-status document) "approved")
               (< block-height (get expiry-block document)))
    false
  )
)

;; Get document type information
(define-read-only (get-document-type (type-id uint))
  (map-get? document-types { type-id: type-id })
)

;; Get document validation history
(define-read-only (get-document-validation-history (document-id uint) (validator principal))
  (map-get? document-validation-history { document-id: document-id, validator: validator })
)

;; Check if document is expired
(define-read-only (is-document-expired (document-id uint))
  (match (map-get? documents { document-id: document-id })
    document (>= block-height (get expiry-block document))
    true
  )
)

;; Check if customer has required documents for verification level
(define-read-only (has-required-documents (customer principal) (verification-level uint))
  (let
    (
      (required-types (get-required-document-types verification-level))
    )
    (check-customer-documents customer required-types)
  )
)

;; Private Functions

;; Get required document types for verification level
(define-private (get-required-document-types (verification-level uint))
  (if (is-eq verification-level u1)
    (list DOC-TYPE-ID DOC-TYPE-PROOF-OF-ADDRESS)
    (if (is-eq verification-level u2)
      (list DOC-TYPE-ID DOC-TYPE-PROOF-OF-ADDRESS DOC-TYPE-INCOME-STATEMENT DOC-TYPE-BANK-STATEMENT)
      (list DOC-TYPE-ID DOC-TYPE-PROOF-OF-ADDRESS DOC-TYPE-INCOME-STATEMENT DOC-TYPE-BANK-STATEMENT DOC-TYPE-EMPLOYMENT-LETTER DOC-TYPE-TAX-RETURN)
    )
  )
)

;; Check if customer has all required documents
(define-private (check-customer-documents (customer principal) (required-types (list 6 uint)))
  (fold check-document-exists required-types true)
)

;; Check if a specific document exists and is validated
(define-private (check-document-exists (document-type uint) (acc bool))
  (and acc
    (match (map-get? customer-documents { customer: tx-sender, document-type: document-type })
      doc-data (is-document-validated (get document-id doc-data))
      false
    )
  )
)

;; Get document validity period
(define-read-only (get-document-validity-period)
  (var-get document-validity-period)
)

;; Get next document ID
(define-read-only (get-next-document-id)
  (var-get next-document-id)
)
