;; Identity Verification Contract
;; Handles customer identity verification and validation

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-IDENTITY-NOT-FOUND (err u201))
(define-constant ERR-IDENTITY-ALREADY-EXISTS (err u202))
(define-constant ERR-INVALID-VERIFICATION-LEVEL (err u203))
(define-constant ERR-VERIFICATION-EXPIRED (err u204))

;; Data Variables
(define-data-var next-identity-id uint u1)
(define-data-var verification-validity-period uint u52560) ;; ~1 year in blocks

;; Verification Levels
(define-constant LEVEL-BASIC u1)
(define-constant LEVEL-ENHANCED u2)
(define-constant LEVEL-PREMIUM u3)

;; Data Maps
(define-map identities
  { identity-id: uint }
  {
    customer: principal,
    identity-hash: (buff 32),
    verification-level: uint,
    verification-status: (string-ascii 20),
    verified-by: (optional principal),
    verification-block: uint,
    expiry-block: uint,
    is-active: bool
  }
)

(define-map identity-by-customer
  { customer: principal }
  { identity-id: uint }
)

(define-map verification-requirements
  { level: uint }
  {
    required-documents: uint,
    specialist-level-required: uint,
    verification-fee: uint
  }
)

(define-map identity-attributes
  { identity-id: uint, attribute: (string-ascii 30) }
  { value-hash: (buff 32), verified: bool }
)

;; Initialize verification requirements
(map-set verification-requirements { level: LEVEL-BASIC }
  { required-documents: u2, specialist-level-required: u1, verification-fee: u100 })
(map-set verification-requirements { level: LEVEL-ENHANCED }
  { required-documents: u4, specialist-level-required: u2, verification-fee: u250 })
(map-set verification-requirements { level: LEVEL-PREMIUM }
  { required-documents: u6, specialist-level-required: u3, verification-fee: u500 })

;; Public Functions

;; Submit identity for verification
(define-public (submit-identity (identity-hash (buff 32)) (verification-level uint))
  (let
    (
      (identity-id (var-get next-identity-id))
      (customer tx-sender)
      (expiry-block (+ block-height (var-get verification-validity-period)))
    )
    (asserts! (is-none (map-get? identity-by-customer { customer: customer })) ERR-IDENTITY-ALREADY-EXISTS)
    (asserts! (and (>= verification-level LEVEL-BASIC) (<= verification-level LEVEL-PREMIUM)) ERR-INVALID-VERIFICATION-LEVEL)

    (map-set identities
      { identity-id: identity-id }
      {
        customer: customer,
        identity-hash: identity-hash,
        verification-level: verification-level,
        verification-status: "pending",
        verified-by: none,
        verification-block: block-height,
        expiry-block: expiry-block,
        is-active: true
      }
    )

    (map-set identity-by-customer
      { customer: customer }
      { identity-id: identity-id }
    )

    (var-set next-identity-id (+ identity-id u1))
    (ok identity-id)
  )
)

;; Verify identity (called by qualified specialist)
(define-public (verify-identity (identity-id uint) (verification-status (string-ascii 20)))
  (let
    (
      (identity (unwrap! (map-get? identities { identity-id: identity-id }) ERR-IDENTITY-NOT-FOUND))
      (specialist tx-sender)
    )
    ;; In a real implementation, we would check specialist qualification here
    ;; For now, we'll allow any principal to verify

    (map-set identities
      { identity-id: identity-id }
      (merge identity {
        verification-status: verification-status,
        verified-by: (some specialist),
        verification-block: block-height
      })
    )
    (ok true)
  )
)

;; Add identity attribute
(define-public (add-identity-attribute (identity-id uint) (attribute (string-ascii 30)) (value-hash (buff 32)))
  (let
    (
      (identity (unwrap! (map-get? identities { identity-id: identity-id }) ERR-IDENTITY-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get customer identity)) ERR-NOT-AUTHORIZED)

    (map-set identity-attributes
      { identity-id: identity-id, attribute: attribute }
      { value-hash: value-hash, verified: false }
    )
    (ok true)
  )
)

;; Verify identity attribute
(define-public (verify-identity-attribute (identity-id uint) (attribute (string-ascii 30)) (verified bool))
  (let
    (
      (identity (unwrap! (map-get? identities { identity-id: identity-id }) ERR-IDENTITY-NOT-FOUND))
      (attr (unwrap! (map-get? identity-attributes { identity-id: identity-id, attribute: attribute }) ERR-IDENTITY-NOT-FOUND))
    )
    ;; In a real implementation, we would check specialist authorization here

    (map-set identity-attributes
      { identity-id: identity-id, attribute: attribute }
      (merge attr { verified: verified })
    )
    (ok true)
  )
)

;; Update identity status
(define-public (update-identity-status (identity-id uint) (is-active bool))
  (let
    (
      (identity (unwrap! (map-get? identities { identity-id: identity-id }) ERR-IDENTITY-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)

    (map-set identities
      { identity-id: identity-id }
      (merge identity { is-active: is-active })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get identity information
(define-read-only (get-identity (identity-id uint))
  (map-get? identities { identity-id: identity-id })
)

;; Get identity by customer
(define-read-only (get-identity-by-customer (customer principal))
  (match (map-get? identity-by-customer { customer: customer })
    identity-data (map-get? identities { identity-id: (get identity-id identity-data) })
    none
  )
)

;; Check if identity is verified
(define-read-only (is-identity-verified (identity-id uint))
  (match (map-get? identities { identity-id: identity-id })
    identity (and
               (get is-active identity)
               (is-eq (get verification-status identity) "verified")
               (< block-height (get expiry-block identity)))
    false
  )
)

;; Get identity attribute
(define-read-only (get-identity-attribute (identity-id uint) (attribute (string-ascii 30)))
  (map-get? identity-attributes { identity-id: identity-id, attribute: attribute })
)

;; Get verification requirements
(define-read-only (get-verification-requirements (level uint))
  (map-get? verification-requirements { level: level })
)

;; Check if identity verification is expired
(define-read-only (is-verification-expired (identity-id uint))
  (match (map-get? identities { identity-id: identity-id })
    identity (>= block-height (get expiry-block identity))
    true
  )
)

;; Get verification validity period
(define-read-only (get-verification-validity-period)
  (var-get verification-validity-period)
)

;; Get next identity ID
(define-read-only (get-next-identity-id)
  (var-get next-identity-id)
)
