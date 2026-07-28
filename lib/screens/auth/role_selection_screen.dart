import 'package:flutter/material.dart';
import 'login_screen.dart';


class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 700;
    return Scaffold(
      backgroundColor: const Color(0xffFAFAFA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 12),

                const Icon(
                  Icons.favorite,
                  color: Colors.red,
                  size: 70,
                ),

                const SizedBox(height: 20),

                Text(
                  "Every drop Counts",
                  style: TextStyle(
                      color: Colors.red.shade400,
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w500
                  ),
                ),

                const SizedBox(height: 16),

                const Text(
                  "Choose Your Role",
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),


                const SizedBox(height: 12),

                Text(
                  "Select how you want to continue",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 40),



                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth > 700;

                      if (!isDesktop) {
                        return GridView.count(
                          crossAxisCount: 1,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          childAspectRatio: 2.3,
                          children: [
                            _roleCard(
                              context,
                              icon: Icons.volunteer_activism,
                              title: "Donor",
                              subtitle: "Donate Blood & Save Lives",
                              color: Colors.red,
                            ),
                            _roleCard(
                              context,
                              icon: Icons.bloodtype,
                              title: "Recipient",
                              subtitle: "Find Blood Quickly",
                              color: Colors.deepPurple,
                            ),
                            _roleCard(
                              context,
                              icon: Icons.local_hospital,
                              title: "Hospital",
                              subtitle: "Manage Emergency Requests",
                              color: Colors.blue,
                            ),
                            _roleCard(
                              context,
                              icon: Icons.inventory_2,
                              title: "Blood Bank",
                              subtitle: "Manage Blood Stock",
                              color: Colors.green,
                            ),
                            _roleCard(
                              context,
                              icon: Icons.medical_services,
                              title: "Doctor",
                              subtitle: "Verify Patients & Coordinate Care",
                              color: Colors.teal,
                            ),
                          ],
                        );
                      }

                      return SingleChildScrollView(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 20,
                          runSpacing: 20,
                          children: [
                            SizedBox(
                              width: 400,
                              height: 200,
                              child: _roleCard(
                                context,
                                icon: Icons.volunteer_activism,
                                title: "Donor",
                                subtitle: "Donate Blood & Save Lives",
                                color: Colors.red,
                              ),
                            ),
                            SizedBox(
                              width: 400,
                              height: 200,
                              child: _roleCard(
                                context,
                                icon: Icons.bloodtype,
                                title: "Recipient",
                                subtitle: "Find Blood Quickly",
                                color: Colors.deepPurple,
                              ),
                            ),
                            SizedBox(
                              width: 400,
                              height: 200,
                              child: _roleCard(
                                context,
                                icon: Icons.local_hospital,
                                title: "Hospital",
                                subtitle: "Manage Emergency Requests",
                                color: Colors.blue,
                              ),
                            ),
                            SizedBox(
                              width: 400,
                              height: 200,
                              child: _roleCard(
                                context,
                                icon: Icons.inventory_2,
                                title: "Blood Bank",
                                subtitle: "Manage Blood Stock",
                                color: Colors.green,
                              ),
                            ),
                            SizedBox(
                              width: 400,
                              height: 200,
                              child: _roleCard(
                                context,
                                icon: Icons.medical_services,
                                title: "Doctor",
                                subtitle: "Verify Patients & Coordinate Care",
                                color: Colors.teal,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleCard(
      BuildContext context, {
        required IconData icon,
        required String title,
        required String subtitle,
        required Color color,
      }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LoginScreen(role: title),
          ),
        );
      },
      child: Ink(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(.18),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: color.withOpacity(.12),
                child: Icon(
                  icon,
                  color: color,
                  size: 32,
                ),
              ),

              const SizedBox(width: 20),

              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.arrow_forward_ios,
                color: color,
              ),
            ],
          ),
        ),
      ),
    );
  }
}