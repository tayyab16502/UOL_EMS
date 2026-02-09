UOL Event Management System (EMS) 

Title: UOL Event Management System (EMS)  

Smart Campus Event Platform with Secure Verification & QR Ticketing 

Developer: Tayyab Khan 

1. Overview (Project Introduction) UOL EMS is a complete mobile application designed to manage events at the University of Lahore easily. It helps the administration create events and allows students to register for them. 

The system is built to handle the entire flow: from a student signing up to entering the event venue using a secure Gatekeeper (Guard) scanning module. It ensures that only verified students can attend events. 

2. Key Features & Logic 

Role-Based Access (Smart Login): The app automatically detects who is logging in and sends them to the right dashboard: 

Students: Can view events and register. 

Admins: Can create events and manage student data. 

Super Admin (CS Dept): Has master control over all other departments. 

Guards: Have a special scanner to check tickets at the gate. 

Smart Verification System: 

Pending Status: When a new student signs up, their status is "Pending." They cannot access the app until approved. 

Approval Stamp: Once an Admin approves a student, their profile card shows a digital stamp: "Approved by: [Admin Name]". 

Class Manager System (Workload Distribution): To help Admins manage thousands of students, an Admin can promote a student to "Class Manager." 

Visual Identity: Managers get a Star Icon and an Orange Border on their profile. 

Power: They get a notification bell to verify pending students from their specific class. 

Department Control Room (Super Admin): 

The Computer Science (CS) Admin is the "Boss." 

Locking System: The Boss can Lock a specific department (e.g., Math). If locked, students and admins of that department cannot log in. 

QR Event Ticketing: 

Registration: Students register for General or Department-specific events. 

Ticket Generation: The app generates a unique QR Code Ticket for the student. 

Gatekeeper Mode: Guards scan this code using the app. The system checks the database in real-time to see if the ticket is valid. 

Automated Database Logic: 

To prevent errors, when an Admin logs in, the system checks if their Department Folder exists in the database. If not, it automatically creates it. 

Dynamic UI & Theme: 

Supports Light and Dark modes with a gradient look. 

Uses local storage to remember the user's theme preference. 

3. Database Structure (Cloud Firestore) The app uses a "Flat Structure" in Firebase for high speed: 

Users Collection: Stores Students, Admins, and Guards. 

Fields: uid, email, role, department, status (pending/approved), isManager (bool), sapId. 

Events Collection: Stores event details. 

Fields: title, date, fee, registeredStudents (Array of IDs). 

Departments Collection: Used for the Locking mechanism. 

Fields: name, isLocked (bool). 

4. Tech Stack (Tools Used) 

Frontend: Flutter (Dart) - Modular Architecture. 

State Management: setState & StreamBuilders (for real-time updates). 

Authentication: Firebase Auth (Email/Password & Google Sign-In). 

Database: Cloud Firestore (NoSQL Real-time Database). 

Testing Tool: Ngrok (Used for initial AI model prototype testing). 

5. Future Work 

Payments: Add Stripe/EasyPaisa for paid events. 

AI Chatbot: A dedicated assistant for student queries. 

Analytics: Graphs for Admins to see registration trends. 
