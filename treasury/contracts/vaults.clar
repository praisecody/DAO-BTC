;; DAO-BTC: Bitcoin-Native Treasury Vaults
;; Version: 1.0.0 - Feature: Bitcoin-Native Treasury Management

;; Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-VAULT-NOT-FOUND (err u101))
(define-constant ERR-INSUFFICIENT-BALANCE (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-MEMBER-EXISTS (err u104))
(define-constant ERR-NOT-MEMBER (err u105))
(define-constant ERR-INSUFFICIENT-SIGNERS (err u106))
(define-constant ERR-VAULT-LOCKED (err u107))

(define-constant MIN-SIGNERS u2)
(define-constant MAX-SIGNERS u10)

;; Data Variables
(define-data-var vault-counter uint u0)

;; Maps
(define-map treasury-vaults
  { vault-id: uint }
  {
    name: (string-ascii 50),
    creator: principal,
    btc-balance: uint,
    stx-balance: uint,
    required-sigs: uint,
    total-members: uint,
    is-locked: bool,
    created-at: uint
  }
)

(define-map vault-members
  { vault-id: uint, member: principal }
  {
    is-signer: bool,
    voting-weight: uint,
    joined-at: uint,
    is-active: bool
  }
)

(define-map vault-signers
  { vault-id: uint }
  { signer-list: (list 10 principal) }
)

(define-map member-deposits
  { vault-id: uint, member: principal }
  { 
    btc-contributed: uint,
    stx-contributed: uint,
    total-deposits: uint
  }
)

(define-map withdrawal-approvals
  { vault-id: uint, withdrawal-id: uint, signer: principal }
  { approved: bool, timestamp: uint }
)

(define-map pending-withdrawals
  { vault-id: uint, withdrawal-id: uint }
  {
    recipient: principal,
    amount: uint,
    asset-type: (string-ascii 10),
    approvals: uint,
    created-at: uint,
    executed: bool
  }
)

;; Read-only functions
(define-read-only (get-vault-info (vault-id uint))
  (map-get? treasury-vaults { vault-id: vault-id })
)

(define-read-only (get-member-info (vault-id uint) (member principal))
  (map-get? vault-members { vault-id: vault-id, member: member })
)

(define-read-only (get-vault-balance (vault-id uint))
  (match (get-vault-info vault-id)
    vault-data
    (ok {
      btc-balance: (get btc-balance vault-data),
      stx-balance: (get stx-balance vault-data),
      total-members: (get total-members vault-data)
    })
    ERR-VAULT-NOT-FOUND
  )
)

(define-read-only (get-member-deposits (vault-id uint) (member principal))
  (map-get? member-deposits { vault-id: vault-id, member: member })
)

(define-read-only (is-vault-member (vault-id uint) (member principal))
  (match (get-member-info vault-id member)
    member-data (get is-active member-data)
    false
  )
)

(define-read-only (is-vault-signer (vault-id uint) (member principal))
  (match (get-member-info vault-id member)
    member-data (and (get is-active member-data) (get is-signer member-data))
    false
  )
)

;; Private functions
(define-private (update-vault-balance (vault-id uint) (amount uint) (asset-type (string-ascii 10)) (operation (string-ascii 10)))
  (match (get-vault-info vault-id)
    vault-data
    (let ((current-btc (get btc-balance vault-data))
          (current-stx (get stx-balance vault-data)))
      (if (is-eq asset-type "BTC")
        (if (is-eq operation "add")
          (map-set treasury-vaults 
            { vault-id: vault-id }
            (merge vault-data { btc-balance: (+ current-btc amount) }))
          (map-set treasury-vaults 
            { vault-id: vault-id }
            (merge vault-data { btc-balance: (- current-btc amount) })))
        (if (is-eq operation "add")
          (map-set treasury-vaults 
            { vault-id: vault-id }
            (merge vault-data { stx-balance: (+ current-stx amount) }))
          (map-set treasury-vaults 
            { vault-id: vault-id }
            (merge vault-data { stx-balance: (- current-stx amount) }))))
      true)
    false
  )
)

;; Public functions

;; Create new treasury vault
(define-public (create-vault (name (string-ascii 50)) (required-sigs uint))
  (let ((vault-id (+ (var-get vault-counter) u1)))
    (asserts! (and (>= required-sigs MIN-SIGNERS) (<= required-sigs MAX-SIGNERS)) ERR-INVALID-AMOUNT)
    (asserts! (> (len name) u0) ERR-INVALID-AMOUNT)
    
    (map-set treasury-vaults
      { vault-id: vault-id }
      {
        name: name,
        creator: tx-sender,
        btc-balance: u0,
        stx-balance: u0,
        required-sigs: required-sigs,
        total-members: u1,
        is-locked: false,
        created-at: stacks-block-height
      }
    )
    
    ;; Add creator as first signer
    (map-set vault-members
      { vault-id: vault-id, member: tx-sender }
      {
        is-signer: true,
        voting-weight: u100,
        joined-at: stacks-block-height,
        is-active: true
      }
    )
    
    ;; Initialize signer list
    (map-set vault-signers
      { vault-id: vault-id }
      { signer-list: (list tx-sender) }
    )
    
    (var-set vault-counter vault-id)
    (ok vault-id)
  )
)

;; Add member to vault
(define-public (add-member (vault-id uint) (new-member principal) (is-signer bool) (voting-weight uint))
  (let ((vault-data (unwrap! (get-vault-info vault-id) ERR-VAULT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get creator vault-data)) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-vault-member vault-id new-member)) ERR-MEMBER-EXISTS)
    (asserts! (not (get is-locked vault-data)) ERR-VAULT-LOCKED)
    (asserts! (<= voting-weight u1000) ERR-INVALID-AMOUNT)
    
    (map-set vault-members
      { vault-id: vault-id, member: new-member }
      {
        is-signer: is-signer,
        voting-weight: voting-weight,
        joined-at: stacks-block-height,
        is-active: true
      }
    )
    
    ;; Update total members count
    (map-set treasury-vaults
      { vault-id: vault-id }
      (merge vault-data { total-members: (+ (get total-members vault-data) u1) })
    )
    
    (ok true)
  )
)

;; Deposit STX to vault
(define-public (deposit-stx (vault-id uint) (amount uint))
  (let ((vault-data (unwrap! (get-vault-info vault-id) ERR-VAULT-NOT-FOUND)))
    (asserts! (is-vault-member vault-id tx-sender) ERR-NOT-MEMBER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (get is-locked vault-data)) ERR-VAULT-LOCKED)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    ;; Update vault balance
    (update-vault-balance vault-id amount "STX" "add")
    
    ;; Update member deposits
    (match (get-member-deposits vault-id tx-sender)
      existing-deposits
      (map-set member-deposits
        { vault-id: vault-id, member: tx-sender }
        {
          btc-contributed: (get btc-contributed existing-deposits),
          stx-contributed: (+ (get stx-contributed existing-deposits) amount),
          total-deposits: (+ (get total-deposits existing-deposits) u1)
        })
      (map-set member-deposits
        { vault-id: vault-id, member: tx-sender }
        {
          btc-contributed: u0,
          stx-contributed: amount,
          total-deposits: u1
        })
    )
    
    (ok amount)
  )
)

;; Simulate BTC deposit (in real implementation, this would monitor Bitcoin addresses)
(define-public (record-btc-deposit (vault-id uint) (member principal) (amount uint))
  (let ((vault-data (unwrap! (get-vault-info vault-id) ERR-VAULT-NOT-FOUND)))
    (asserts! (is-vault-signer vault-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-vault-member vault-id member) ERR-NOT-MEMBER)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    
    ;; Update vault BTC balance
    (update-vault-balance vault-id amount "BTC" "add")
    
    ;; Update member deposits
    (match (get-member-deposits vault-id member)
      existing-deposits
      (map-set member-deposits
        { vault-id: vault-id, member: member }
        {
          btc-contributed: (+ (get btc-contributed existing-deposits) amount),
          stx-contributed: (get stx-contributed existing-deposits),
          total-deposits: (+ (get total-deposits existing-deposits) u1)
        })
      (map-set member-deposits
        { vault-id: vault-id, member: member }
        {
          btc-contributed: amount,
          stx-contributed: u0,
          total-deposits: u1
        })
    )
    
    (ok amount)
  )
)

;; Request withdrawal (requires multi-sig approval)
(define-public (request-withdrawal (vault-id uint) (withdrawal-id uint) (recipient principal) (amount uint) (asset-type (string-ascii 10)))
  (let ((vault-data (unwrap! (get-vault-info vault-id) ERR-VAULT-NOT-FOUND)))
    (asserts! (is-vault-signer vault-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (not (get is-locked vault-data)) ERR-VAULT-LOCKED)
    
    ;; Check sufficient balance
    (if (is-eq asset-type "STX")
      (asserts! (<= amount (get stx-balance vault-data)) ERR-INSUFFICIENT-BALANCE)
      (asserts! (<= amount (get btc-balance vault-data)) ERR-INSUFFICIENT-BALANCE)
    )
    
    (map-set pending-withdrawals
      { vault-id: vault-id, withdrawal-id: withdrawal-id }
      {
        recipient: recipient,
        amount: amount,
        asset-type: asset-type,
        approvals: u1,
        created-at: stacks-block-height,
        executed: false
      }
    )
    
    ;; Auto-approve from requester
    (map-set withdrawal-approvals
      { vault-id: vault-id, withdrawal-id: withdrawal-id, signer: tx-sender }
      { approved: true, timestamp: stacks-block-height }
    )
    
    (ok withdrawal-id)
  )
)

;; Approve withdrawal
(define-public (approve-withdrawal (vault-id uint) (withdrawal-id uint))
  (let ((vault-data (unwrap! (get-vault-info vault-id) ERR-VAULT-NOT-FOUND))
        (withdrawal-data (unwrap! (map-get? pending-withdrawals { vault-id: vault-id, withdrawal-id: withdrawal-id }) ERR-VAULT-NOT-FOUND)))
    
    (asserts! (is-vault-signer vault-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (get executed withdrawal-data)) ERR-VAULT-LOCKED)
    
    ;; Record approval
    (map-set withdrawal-approvals
      { vault-id: vault-id, withdrawal-id: withdrawal-id, signer: tx-sender }
      { approved: true, timestamp: stacks-block-height }
    )
    
    ;; Update approval count
    (map-set pending-withdrawals
      { vault-id: vault-id, withdrawal-id: withdrawal-id }
      (merge withdrawal-data { approvals: (+ (get approvals withdrawal-data) u1) })
    )
    
    (ok true)
  )
)

;; Execute withdrawal (when enough approvals)
(define-public (execute-withdrawal (vault-id uint) (withdrawal-id uint))
  (let ((vault-data (unwrap! (get-vault-info vault-id) ERR-VAULT-NOT-FOUND))
        (withdrawal-data (unwrap! (map-get? pending-withdrawals { vault-id: vault-id, withdrawal-id: withdrawal-id }) ERR-VAULT-NOT-FOUND)))
    
    (asserts! (is-vault-signer vault-id tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get approvals withdrawal-data) (get required-sigs vault-data)) ERR-INSUFFICIENT-SIGNERS)
    (asserts! (not (get executed withdrawal-data)) ERR-VAULT-LOCKED)
    
    ;; Execute STX withdrawal
    (if (is-eq (get asset-type withdrawal-data) "STX")
      (begin
        (try! (as-contract (stx-transfer? (get amount withdrawal-data) tx-sender (get recipient withdrawal-data))))
        (update-vault-balance vault-id (get amount withdrawal-data) "STX" "sub")
      )
      ;; For BTC, just update internal accounting (actual BTC transfer handled off-chain)
      (update-vault-balance vault-id (get amount withdrawal-data) "BTC" "sub")
    )
    
    ;; Mark as executed
    (map-set pending-withdrawals
      { vault-id: vault-id, withdrawal-id: withdrawal-id }
      (merge withdrawal-data { executed: true })
    )
    
    (ok (get amount withdrawal-data))
  )
)

;; Emergency lock vault
(define-public (lock-vault (vault-id uint))
  (let ((vault-data (unwrap! (get-vault-info vault-id) ERR-VAULT-NOT-FOUND)))
    (asserts! (is-eq tx-sender (get creator vault-data)) ERR-NOT-AUTHORIZED)
    
    (map-set treasury-vaults
      { vault-id: vault-id }
      (merge vault-data { is-locked: true })
    )
    
    (ok true)
  )
)

;; Get vault summary
(define-read-only (get-vault-summary (vault-id uint))
  (match (get-vault-info vault-id)
    vault-data
    (ok {
      name: (get name vault-data),
      creator: (get creator vault-data),
      btc-balance: (get btc-balance vault-data),
      stx-balance: (get stx-balance vault-data),
      total-members: (get total-members vault-data),
      required-sigs: (get required-sigs vault-data),
      is-locked: (get is-locked vault-data)
    })
    ERR-VAULT-NOT-FOUND
  )
)