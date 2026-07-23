import 'package:flutter/material.dart';



import '../ui/brand.dart';

import '../ui/report_widgets.dart';

import 'relatorios/report_screens.dart';



class RelatoriosScreen extends StatelessWidget {

  const RelatoriosScreen({super.key});



  @override

  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: Brand.bg,

      appBar: AppBar(

        title: const Text('Relatórios'),

        backgroundColor: Brand.blue,

        foregroundColor: Colors.white,

        elevation: 0,

      ),

      body: ListView(

        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),

        children: [

          const Text(

            'Vendas e clientes usam dados sincronizados. Comissão exige conexão com o ERP.',

            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.35),

          ),

          const SizedBox(height: 14),

          ReportMenuTile(

            title: 'Minhas vendas',

            subtitle: 'Filtre por hoje, semana, mês ou período',

            icon: Icons.trending_up_rounded,

            color: Brand.blue,

            onTap: () => _abrir(context, const MinhasVendasReportScreen()),

          ),

          const SizedBox(height: 10),

          ReportMenuTile(

            title: 'Minhas comissões',

            subtitle: 'Online · alíquotas do colaborador',

            icon: Icons.payments_outlined,

            color: const Color(0xFF7C3AED),

            onTap: () => _abrir(context, const ComissoesReportScreen()),

          ),

          const SizedBox(height: 10),

          ReportMenuTile(

            title: 'Clientes atendidos',

            subtitle: 'Filtre por período · visão compacta',

            icon: Icons.people_alt_rounded,

            color: const Color(0xFF0D9488),

            onTap: () => _abrir(context, const ClientesAtendidosReportScreen()),

          ),

          const SizedBox(height: 10),

          ReportMenuTile(

            title: 'Clientes sem compra',

            subtitle: '15, 30, 60 ou 90 dias',

            icon: Icons.person_off_outlined,

            color: const Color(0xFFEA580C),

            onTap: () => _abrir(context, const ClientesSemCompraReportScreen()),

          ),

          const SizedBox(height: 10),

          ReportMenuTile(

            title: 'Contas em aberto',

            subtitle: 'Clientes da sua carteira',

            icon: Icons.request_quote_rounded,

            color: const Color(0xFFDC2626),

            onTap: () => _abrir(context, const ContasAbertoReportScreen()),

          ),

          const SizedBox(height: 10),

          ReportMenuTile(

            title: 'Visitas realizadas',

            subtitle: 'Filtre por hoje, semana, mês ou período',

            icon: Icons.location_on_outlined,

            color: const Color(0xFF64748B),

            onTap: () => _abrir(context, const VisitasReportScreen()),

          ),

        ],

      ),

    );

  }



  void _abrir(BuildContext context, Widget tela) {

    Navigator.push(context, MaterialPageRoute(builder: (_) => tela));

  }

}


